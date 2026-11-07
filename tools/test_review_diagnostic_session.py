"""Meaningful offline-session regressions; synthetic data only, no EFI or GPU."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("session_review_test_subject",
                                             Path(__file__).with_name("review_diagnostic_session.py"))
session = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(session)


def graph_capture(*, graph_only=True, complete=True, identities=()):
    lines = ["gpu-console-graph-v1 observational-only; no-detach no-unlock no-nvram-write"]
    if graph_only:
        lines.append("capture-scope=graph-only no-gpu-mmio no-prom no-image-dump")
    for index, identity in enumerate(identities):
        words = [identity, 0x00100003, 0x030000a1] + [0] * 13
        words[11] = 0x123410de
        lines.extend(("handle id=0x%x" % (index + 1),
                      "protocol guid=4cf5b200-68b8-4ca5-9eec-b23e3f50029a",
                      "pci config-dwords=" + " ".join("%08x" % value for value in words)))
    lines += ["capture-complete=%d" % complete,
              "diagnostic-result status=" + ("0x0000000000000000" if complete else "0x8000000000000006")]
    return ("\n".join(lines) + "\n").encode("ascii")


def nvgop_fixture():
    """A small real loaded-PE fixture accepted by the trusted code-range reader."""
    rva, size, length = 0x280, 0x4000, 0x500
    image = bytearray(size)
    image[:2] = b"MZ"
    struct.pack_into("<I", image, 0x3c, 0x80)
    image[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HH", image, 0x84, 0x8664, 1)
    struct.pack_into("<H", image, 0x94, 0xf0)
    struct.pack_into("<H", image, 0x98, 0x20b)
    struct.pack_into("<II", image, 0x98 + 56, size, 0x200)
    struct.pack_into("<I", image, 0x98 + 108, 16)
    struct.pack_into("<8sII", image, 0x188, b".text", length, rva)
    struct.pack_into("<I", image, 0x188 + 36, 0x60000020)
    name = (session.Readers().nvgop.mp.NVGOP_NAME + "\0").encode("utf-16-le")
    node = bytes((4, 4)) + (4 + len(name)).to_bytes(2, "little") + name
    text = ("binding handle=0x1 image=0x2 version=0x6000a stop=0x100280\n"
            "img base=0x100000\nimg size=0x4000\nimg dump index=00\n"
            "img-path-node raw=" + node.hex() + "\nimg-path-node raw=7fff0400\n")
    return text.encode("ascii"), bytes(image)


def command_log():
    return ("[Decode] PCI Command before: 0x0\n"
            "[Decode] PCI Command after: 0x2 (IO=DISABLED)\n"
            "restore PCI command: actual=0x2 original=0x2 mask=0x6\n"
            "Transaction result=0 safe=1 retained=0 started=1 quiesced=1 flrs=1 DMA_live=0\n")


def gop_record(phase="phase", *, index=0, base="0", size="0"):
    return ("GOPDIAG %s: [%d] handle=0xdeadbeef target=1 max_mode=2 mode=1 "
            "fb_base=%s fb_size=%s hres=1920 vres=1080\n" % (phase, index, base, size))


def legacy_wrapper_log():
    return ("GOP[0] handle=0xdeadbeef mode=0 max=14 info_bytes=36 framebuffer=0x7000000000 bytes=35389440\n"
            "restore PCI command: actual=0x2 original=0x2 mask=0x6\n"
            "BME containment: attribute_status=0 hardware_status=0 command=0x2 cached=0x200 pending=0\n"
            "transaction result=0 containment=0 started=1 quiesced=1 fault=0 retained=0 maps=0 FLR=1\n"
            "GOP SetMode status=0\n"
            "BME containment: attribute_status=0 hardware_status=0 command=0x3 cached=0x200 pending=0\n"
            "FINAL status=0x8000000000000007 stage=post-unlock-handoff attempted=1 driver_release=1 clean=0 containment=0 pci_available=1\n")


class SessionReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="private-session-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def assert_scope(self, result):
        self.assertFalse(result["hardware_tested"])
        self.assertFalse(result["write_eligible"])
        for key in ("CapturedCodeExecuted", "HardwareAccess", "ProfileGenerated",
                    "FirmwareOrSettingsChanged", "NewCaptureRequested",
                    "DriverReleaseVerified", "WindowsRecoveryVerified"):
            self.assertFalse(result["Scope"][key])
        self.assertNotIn(str(self.root), json.dumps(result))

    def test_empty_folder_is_a_useful_report_not_a_retry_request(self):
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(result["Observations"], [])
        self.assertEqual(result["NextAction"]["Code"], "review_input_folder")
        self.assert_scope(result)

    def test_unknown_and_mixed_vendor_graphs_do_not_require_machine_admission(self):
        # Intel, AMD, unlisted NVIDIA and another vendor remain useful observations.
        data = graph_capture(identities=(0xa7808086, 0x164e1002, 0xffff10de, 0x99991234))
        self.write("DIAG00.TXT", data)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        rows = result["Observations"][0]["DisplayIdentityObservations"]
        self.assertEqual({row["Vendor"] for row in rows}, {"8086", "1002", "10de", "1234"})
        stage = [row for row in result["Stages"] if row["Name"] == "compatibility"][0]
        self.assertEqual(stage["Status"], "not_applicable")
        self.assert_scope(result)

    def test_explicit_refusal_and_inner_probe_success_are_not_launcher_errors(self):
        self.write("DIAG00.TXT", (
            b"probe-target seg=0x0000 bus=0x0001 dev=0x0000 fun=0x0000\n"
            b"incomplete reason=probe-unreviewed-envelope status=0x8000000000000003\n"
            b"probe status=0x0000000000000000\n"
            b"capture-complete=0\ndiagnostic-result status=0x8000000000000006\n"))
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        observation = result["Observations"][0]
        self.assertEqual(observation["Completion"], "incomplete")
        self.assertEqual(observation["IncompleteReasons"][0]["Code"], "probe-unreviewed-envelope")
        stage = [row for row in result["Stages"] if row["Name"] == "compatibility"][0]
        self.assertEqual(stage["Status"], "invalid_data")
        self.assertIn("probe_envelope_refused", [row["Code"] for row in stage["Checks"]])
        self.assert_scope(result)

    def test_partial_malformed_and_conflicting_markers_remain_observations(self):
        for index, data in enumerate((b"some partial data\n",
                                      b"capture-complete=1\ncapture-complete=0\n",
                                      b"\xffPRIVATE-BYTES",
                                      b"capture-complete=1\ndiagnostic-result status=not-a-status\n")):
            self.write("DIAG%02d.TXT" % index, data)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual([row["Completion"] for row in result["Observations"]],
                         ["partial_or_unrecognized", "ambiguous_markers",
                          "unreadable_text", "partial_or_unrecognized"])
        self.assertNotIn("PRIVATE-BYTES", json.dumps(result))
        self.assert_scope(result)

    def test_nested_sets_never_borrow_another_folders_saved_images(self):
        text, image = nvgop_fixture()
        self.write("first/DIAG00.TXT", text)
        self.write("first/IMG00.BIN", image)
        self.write("second/DIAG00.TXT", text)
        self.write("third/DIAG00.TXT", graph_capture())
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        codes = [row for row in result["Stages"] if row["Name"] == "nvgop_code"]
        self.assertEqual([row["Status"] for row in codes], ["observed", "unavailable", "unavailable"])
        self.assertEqual(codes[0]["ImageSha256"], hashlib.sha256(image).hexdigest())
        self.assertEqual(codes[0]["CodeSha256"], hashlib.sha256(bytes(0x500)).hexdigest())
        self.assertEqual(codes[0]["FamilyCodeMatches"], [])  # no synthetic admission
        self.assertEqual(codes[1]["Code"], "saved_images_not_present")
        self.assertEqual(len({row["SetId"] for row in result["Observations"]}), 3)
        self.assert_scope(result)

    def test_all_graph_logs_are_summarized_beyond_legacy_cli_four_log_limit(self):
        for index in range(6):
            self.write("DIAG%02d.TXT" % index, graph_capture())
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(len(result["Observations"]), 6)
        self.assertTrue(all(row["Layout"] == "graph_only" for row in result["Observations"]))

    def test_crlf_and_non_ascii_paths_preserve_byte_hashes_and_privacy(self):
        private = "private-user-秘密-12345678-1234-1234-1234-123456789abc"
        data = graph_capture(identities=(0x250410de,)).replace(b"\n", b"\r\n")
        data += ("image-file-path " + private + "\r\n"
                 "incomplete reason=" + private + " status=0x8000000000000006\r\n").encode("utf-8")
        self.write(private + "/diag00.txt", data)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(result["InputFiles"][0]["Sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(result["InputFiles"][0]["Name"], "DIAG00.TXT")
        serialized = json.dumps(result, ensure_ascii=False)
        self.assertNotIn(private, serialized)
        self.assertNotIn("4cf5b200-68b8-4ca5-9eec-b23e3f50029a", serialized)
        self.assertNotIn("image-file-path", serialized)
        self.assert_scope(result)

    def test_unchanged_cache_skips_readers_but_byte_and_membership_changes_do_not(self):
        path = self.write("DIAG00.TXT", graph_capture())
        first = session.review(self.root)
        self.assertEqual(first["Status"], "reviewed", first)
        with patch.object(session, "Readers", side_effect=AssertionError("cached analysis must skip readers")):
            cached = session.review(self.root, previous_cache_key=first["CacheKey"])
        self.assertTrue(cached["Unchanged"], cached)
        before = path.stat()
        data = path.read_bytes().replace(b"capture-complete=1", b"capture-complete=0")
        path.write_bytes(data)  # same length, then restore mtime to defeat metadata-only caching
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        changed = session.review(self.root, previous_cache_key=first["CacheKey"])
        self.assertFalse(changed["Unchanged"])
        self.assertNotEqual(changed["InputDigest"], first["InputDigest"])
        self.write("private-unrelated.txt", b"not executed")
        added = session.review(self.root, previous_cache_key=changed["CacheKey"])
        self.assertFalse(added["Unchanged"])
        self.assertNotEqual(added["InputDigest"], changed["InputDigest"])

    def test_input_drift_during_analysis_refuses_reuse(self):
        path = self.write("DIAG00.TXT", graph_capture())
        original = session.analyze_snapshot

        def change_after_snapshot(saved, readers):
            result = original(saved, readers)
            path.write_bytes(graph_capture(complete=False))
            return result

        with patch.object(session, "analyze_snapshot", side_effect=change_after_snapshot):
            result = session.review(self.root)
        self.assertEqual(result["Status"], "input_refused")
        self.assertRegex(result["CacheKey"], r"^[0-9a-f]{64}$")
        self.assertFalse(result["CacheReusable"])
        self.assertFalse(result["Unchanged"])
        self.assertEqual(result["Stages"][-1]["Code"], "input_changed")

    def test_reader_source_drift_invalidates_result_and_cache(self):
        self.write("DIAG00.TXT", graph_capture())
        with patch.object(session, "_source_manifest", side_effect=["a" * 64, "b" * 64]):
            result = session.review(self.root)
        self.assertEqual(result["Status"], "tool_error")
        self.assertRegex(result["CacheKey"], r"^[0-9a-f]{64}$")
        self.assertFalse(result["CacheReusable"])

    def test_bounds_cover_file_size_total_files_entries_depth_and_captures(self):
        self.write("DIAG00.TXT", graph_capture())
        self.write("IMG00.BIN", b"12345678")
        cases = (("MAX_FILE_BYTES", 4, "input_size_limit"),
                 ("MAX_TOTAL_BYTES", 4, "input_size_limit"),
                 ("MAX_FILES", 1, "input_file_limit"),
                 ("MAX_ENTRIES", 1, "input_entry_limit"),
                 ("MAX_CAPTURES", 0, "input_capture_limit"))
        for setting, value, code in cases:
            with self.subTest(setting=setting), patch.object(session, setting, value):
                result = session.review(self.root)
                self.assertEqual(result["Status"], "input_refused", result)
                self.assertEqual(result["Stages"][-1]["Code"], code)
        self.write("nested/DIAG00.TXT", graph_capture())
        with patch.object(session, "MAX_DEPTH", 0):
            result = session.review(self.root)
        self.assertEqual(result["Stages"][-1]["Code"], "input_depth_limit")

    def test_reparse_attribute_is_refused_even_without_symlink_mode(self):
        self.write("DIAG00.TXT", graph_capture())
        original = Path.lstat

        class Reparse:
            def __init__(self, info):
                self.st_mode = info.st_mode
                self.st_file_attributes = session.REPARSE_POINT

        def injected(path, *args, **kwargs):
            result = original(path, *args, **kwargs)
            return Reparse(result) if path == self.root else result

        with patch.object(Path, "lstat", injected):
            result = session.review(self.root)
        self.assertEqual(result["Status"], "input_refused", result)
        self.assertEqual(result["Stages"][-1]["Code"], "linked_path_refused")

    def test_symlink_and_ancestor_escape_are_refused(self):
        target = self.write("private-target/DIAG00.TXT", graph_capture())
        link = self.root / "escape"
        try:
            link.symlink_to(target.parent, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("This Windows token cannot create symlinks; reparse attributes tested separately")
        result = session.review(link)
        self.assertEqual(result["Status"], "input_refused")
        self.assertEqual(result["Stages"][-1]["Code"], "linked_path_refused")
        result = session.review(self.root)
        self.assertEqual(result["Status"], "input_refused")

    def test_snapshot_adapter_does_not_allow_path_escape(self):
        folder = session.MemoryFolder({"DIAG00.TXT": b"x", "IMG00.BIN": b"image"})
        for name in ("../IMG00.BIN", r"..\IMG00.BIN", "/outside", "a/b", ".."):
            with self.subTest(name=name), self.assertRaises(FileNotFoundError):
                folder / name

    def test_original_bytes_unchanged_no_child_process_or_captured_python_executes(self):
        data = graph_capture()
        diag = self.write("DIAG00.TXT", data)
        payload = self.write("review-nvgop-code.py", b"raise AssertionError('CAPTURED CODE EXECUTED')")
        with patch("subprocess.run", side_effect=AssertionError("No subprocess allowed")), \
                patch("subprocess.Popen", side_effect=AssertionError("No process allowed")):
            result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(diag.read_bytes(), data)
        self.assertEqual(payload.read_bytes(), b"raise AssertionError('CAPTURED CODE EXECUTED')")
        self.assertNotIn("CAPTURED CODE", json.dumps(result))
        self.assert_scope(result)

    def test_edid_private_guid_is_hashed_not_exported(self):
        self.write("DIAG00.TXT", graph_capture())
        readers = session.Readers()
        guid = "e1ff8a3d-0a1f-49c2-67d3-930bcaee7798"
        observed = {"bindings": [{"protocol": "discovered", "version": 16, "file_guid": guid,
                                  "reviewed_mouse_identity_match": False}],
                    "discovered_by_driver_count": 1, "active_by_driver_count": 0}
        with patch.object(readers.edid, "review", return_value=observed):
            row = session._edid_stage("fixture", readers, "file0001")
        self.assertNotIn(guid, json.dumps(row))
        self.assertEqual(row["Bindings"][0]["OwnerIdentitySha256"],
                         hashlib.sha256(guid.encode("ascii")).hexdigest())
        self.assertFalse(row["no_edid_driver_authorized"])

    def test_cli_refused_capture_is_exit_zero_and_missing_input_is_exit_two(self):
        self.write("DIAG00.TXT", graph_capture(complete=False))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = session.main([str(self.root)])
        self.assertEqual(code, 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result["Status"], "reviewed")
        with contextlib.redirect_stdout(io.StringIO()):
            code = session.main([str(self.root / "missing")])
        self.assertEqual(code, 2)

    def test_error_cache_keys_cannot_skip_review_and_installation_error_is_exit_three(self):
        missing = self.root / "missing"
        failed = session.review(missing)
        self.assertRegex(failed["CacheKey"], r"^[0-9a-f]{64}$")
        self.assertFalse(failed["CacheReusable"])
        again = session.review(missing, previous_cache_key=failed["CacheKey"])
        self.assertEqual(again["Status"], "input_refused")
        self.assertFalse(again["Unchanged"])
        self.write("DIAG00.TXT", graph_capture())
        with patch.object(session, "Readers", side_effect=FileNotFoundError("PRIVATE PATH")):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = session.main([str(self.root)])
        self.assertEqual(code, 3)
        result = json.loads(output.getvalue())
        self.assertRegex(result["CacheKey"], r"^[0-9a-f]{64}$")
        self.assertFalse(result["CacheReusable"])
        self.assertNotIn("PRIVATE PATH", output.getvalue())

    def test_unreadable_diag_cannot_disappear_from_compatibility_set(self):
        text, image = nvgop_fixture()
        self.write("DIAG00.TXT", text)
        self.write("DIAG01.TXT", b"\xffPRIVATE")
        self.write("IMG00.BIN", image)
        result = session.review(self.root)
        stage = [row for row in result["Stages"] if row["Name"] == "compatibility"][0]
        self.assertEqual(result["Status"], "reviewed")
        self.assertEqual(stage["Status"], "invalid_data")
        self.assertEqual(stage["Checks"][0]["Code"], "observations_invalid")

    def test_complete_fixture_preserves_direct_checker_admission_result(self):
        path = session.REPO / "research" / "profile" / "test_compatibility.py"
        spec = importlib.util.spec_from_file_location("session_real_checker_fixture", path)
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        builder = fixture.CompatibilityTests()
        builder.folder = self.root
        builder.populate(no_edid=False, count=2)
        readers = session.Readers()
        direct = readers.checker.check(self.root, readers.envelope)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        stage = [row for row in result["Stages"] if row["Name"] == "compatibility"][0]
        self.assertEqual(stage["Status"], direct["status"])
        self.assertEqual([(row["State"], row["Code"]) for row in stage["Checks"]],
                         [(row["state"], row["code"]) for row in direct["checks"]])
        self.assert_scope(result)

    def test_crlf_command_log_is_reviewed_once_without_wrapper_restore_claim(self):
        raw = b"\xef\xbb\xbf" + command_log().replace("\n", "\r\n").encode("utf-8")
        path = self.write("saved-custom-run.TXT", raw)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(result["Observations"][0]["Layout"], "saved_command_log")
        stage = result["Stages"][0]
        self.assertEqual(stage["Name"], "command_boundaries")
        self.assertEqual(stage["Status"], "observed")
        self.assertEqual((stage["DecodeBefore"], stage["DecodeAfter"]), (0, 2))
        self.assertTrue(stage["Transaction"]["Safe"])
        self.assertTrue(stage["TransactionOriginalDiffersFromWrapperEntry"])
        self.assertFalse(stage["WrapperEntryRestorationVerified"])
        self.assertEqual(result["InputFiles"][0]["Sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(path.read_bytes(), raw)
        self.assertTrue(session.review(self.root, previous_cache_key=result["CacheKey"])["Unchanged"])
        self.assert_scope(result)

    def test_gop_missing_and_partial_framebuffers_remain_distinct_observations(self):
        raw = (gop_record("PRIVATE-PHASE", index=0) +
               gop_record("PRIVATE-PHASE", index=1, base="0x12345678")).encode("ascii")
        self.write("saved-graphics.log", raw)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        stage = result["Stages"][0]
        self.assertEqual(stage["Name"], "gop_records")
        self.assertEqual(stage["Status"], "observed")
        rows = stage["Records"]
        self.assertEqual([row["Classification"] for row in rows],
                         ["present-without-framebuffer", "partial-framebuffer"])
        self.assertTrue(rows[0]["FramebufferAbsent"])
        self.assertTrue(rows[1]["FramebufferPartial"])
        self.assertEqual(rows[0]["PhaseId"], rows[1]["PhaseId"])
        self.assertFalse(stage["AncestryIndependentlyVerified"])
        self.assertFalse(stage["FramebufferGeometryVerified"])
        self.assertFalse(stage["SetModeAuthorized"])
        self.assertFalse(stage["ConnectControllerAuthorized"])
        for private in ("PRIVATE-PHASE", "0xdeadbeef", "0x12345678"):
            self.assertNotIn(private, json.dumps(result))
        self.assert_scope(result)

    def test_arbitrary_text_filename_dispatches_both_readers_without_private_content(self):
        private = "PRIVATE-NAME-秘密-12345678-1234-1234-1234-123456789abc"
        raw = (command_log() + gop_record("PRIVATE-PHASE") +
               "private path=C:\\Users\\" + private + "\n"
               "device instance=PCI\\VEN_10DE&PRIVATE-INSTANCE\n"
               "public buffer=PRIVATE-BUFFER\n").encode("utf-8")
        self.write(private + "/" + private + ".LoG", raw)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual({row["Name"] for row in result["Stages"]},
                         {"command_boundaries", "gop_records"})
        self.assertEqual(len(result["Observations"]), 2)
        self.assertNotIn("Name", result["InputFiles"][0])
        self.assertEqual(result["InputFiles"][0]["Sha256"], hashlib.sha256(raw).hexdigest())
        for hidden in (private, "PRIVATE-PHASE", "PRIVATE-INSTANCE", "PRIVATE-BUFFER",
                       "0xdeadbeef", "C:\\Users"):
            self.assertNotIn(hidden, json.dumps(result, ensure_ascii=False))
        self.assertEqual(result["NextAction"]["Code"], "review_existing_evidence")
        self.assert_scope(result)

    def test_malformed_recognized_text_is_partial_not_silently_omitted(self):
        cases = {
            "command.txt": b"[Decode] PRIVATE-MALFORMED\n",
            "gop.log": b"GOPDIAG PRIVATE-MALFORMED\n",
            "encoding.log": b"GOPDIAG \xffPRIVATE-MALFORMED\n",
            "extra-gop.log": (gop_record() + "GOPDIAG PRIVATE-MALFORMED\n").encode("ascii"),
            "extra-command.log": (command_log() + "Transaction result=PRIVATE-MALFORMED\n").encode("ascii"),
            "bad-restore.log": command_log().replace(
                "restore PCI command: actual=0x2 original=0x2 mask=0x6",
                "restore PCI command: PRIVATE-MALFORMED").encode("ascii"),
            "line-bound.log": b"GOPDIAG " + b"x" * (session.MAX_LINE_BYTES + 1),
        }
        for name, data in cases.items():
            self.write(name, data)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(len(result["Observations"]), len(cases))
        self.assertTrue(all(row["Completion"] == "partial" for row in result["Observations"]))
        self.assertTrue(all(row["Status"] == "partial" for row in result["Stages"]))
        self.assertEqual({row["Code"] for row in result["Stages"]},
                         {"command_records_partial_or_invalid", "gop_records_partial_or_invalid",
                          "command_markers_not_fully_reviewed", "gop_markers_not_fully_reviewed"})
        self.assertNotIn("PRIVATE-MALFORMED", json.dumps(result))
        self.assert_scope(result)

    def test_legacy_wrapper_preserves_reported_final_failure_without_recovery_or_cache_inference(self):
        raw = b"\xef\xbb\xbf" + legacy_wrapper_log().replace("\n", "\r\n").encode("ascii")
        path = self.write("PRIVATE-wrapper.TXT", raw)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        self.assertEqual(len(result["Stages"]), 1)
        stage = result["Stages"][0]
        self.assertEqual((stage["Name"], stage["Status"]),
                         ("legacy_wrapper", "partial"))
        self.assertEqual(stage["TransactionRecords"][0]["Result"], 0)
        self.assertEqual(stage["TransactionRecords"][0]["ContainmentStatus"], "0x0000000000000000")
        self.assertEqual(stage["SetModeRecords"][0]["Status"], "0x0000000000000000")
        final = stage["FinalRecords"][0]
        self.assertEqual(final["Status"], "0x8000000000000007")
        self.assertEqual(final["Phase"], "post-unlock-handoff")
        self.assertFalse(final["CleanReported"])
        self.assertEqual([row["ReportedCommand"] for row in stage["ContainmentRecords"]], [2, 3])
        self.assertEqual([row["LoggedCachedAttributes"] for row in stage["ContainmentRecords"]],
                         ["0x0000000000000200", "0x0000000000000200"])
        self.assertTrue(all(not row["Pending"] for row in stage["ContainmentRecords"]))
        for key in ("WrapperEntryRestorationVerified", "CacheConsistencyVerified",
                    "WindowsRecoveryVerified", "UnlockVerified"):
            self.assertFalse(stage[key])
        self.assertEqual(result["Observations"][0]["Completion"], "partial")
        self.assertEqual(path.read_bytes(), raw)
        self.assertEqual(result["InputFiles"][0]["Sha256"], hashlib.sha256(raw).hexdigest())
        for private in ("PRIVATE-wrapper", "0xdeadbeef", "0x7000000000"):
            self.assertNotIn(private, json.dumps(result))
        self.assert_scope(result)

    def test_legacy_malformed_ambiguous_and_excess_records_stay_bounded_partial(self):
        private = "PRIVATE-12345678-1234-1234-1234-123456789abc"
        text = legacy_wrapper_log().replace("started=1", "started=2")
        text += "transaction result=PRIVATE-MALFORMED\n"
        text += "BME containment: attribute_status=0 hardware_status=0 command=0x10000 cached=0x200 pending=0\n"
        text += ("FINAL status=0 stage=" + private +
                 " attempted=1 driver_release=1 clean=1 containment=0 pci_available=1\n")
        text += "GOP SetMode status=0\n" * 40
        self.write("PRIVATE-wrapper.LOG", text.encode("ascii"))
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        stage = result["Stages"][0]
        self.assertEqual(stage["Status"], "partial")
        self.assertEqual(stage["MalformedRecordCount"], 3)
        self.assertEqual(stage["TransactionRecords"], [])
        self.assertEqual(len(stage["FinalRecords"]), 2)  # no last-record-wins success
        self.assertEqual(stage["FinalRecords"][1]["Phase"], "unclassified_phase")
        self.assertEqual(stage["FinalRecords"][1]["PhaseSha256"],
                         hashlib.sha256(private.encode("ascii")).hexdigest())
        self.assertEqual(len(stage["SetModeRecords"]), 32)
        self.assertEqual(stage["TruncatedRecordCount"], 9)
        self.assertNotIn(private, json.dumps(result))
        self.assertNotIn("PRIVATE-MALFORMED", json.dumps(result))
        self.assertFalse(stage["UnlockVerified"])
        self.assertFalse(stage["WindowsRecoveryVerified"])
        self.assert_scope(result)

        # Reject excessive numeric text before int conversion, independently of
        # Python's version-specific global decimal-conversion limit.
        oversized = ("transaction result=" + "9" * 60000 +
                     " containment=0 started=1 quiesced=1 fault=0 retained=0 maps=0 FLR=1\n")
        with patch.object(session, "int", side_effect=AssertionError("numeric conversion must not run"),
                          create=True):
            bounded = session._legacy_wrapper_values(oversized)
        self.assertEqual(bounded["MalformedRecordCount"], 1)
        self.assertEqual(bounded["TransactionRecords"], [])

        # The C producer prints EFI containment status and cached attributes as
        # UINT64 hex values; JSON must preserve all bits across Windows readers.
        nonzero = legacy_wrapper_log().replace("containment=0", "containment=0x8000000000000007")
        nonzero = nonzero.replace("cached=0x200", "cached=0x8000000000000200")
        reported = session._legacy_wrapper_values(nonzero)
        self.assertEqual(reported["MalformedRecordCount"], 0)
        self.assertEqual(reported["TransactionRecords"][0]["ContainmentStatus"], "0x8000000000000007")
        self.assertEqual(reported["FinalRecords"][0]["ContainmentStatus"], "0x8000000000000007")
        self.assertEqual(reported["ContainmentRecords"][0]["LoggedCachedAttributes"],
                         "0x8000000000000200")
        short_final = ("FINAL status=0x8000000000000007 stage=post-unlock-handoff "
                       "attempted=1 driver_release=1 clean=0\n")
        reported = session._legacy_wrapper_values(short_final)
        self.assertEqual(reported["MalformedRecordCount"], 0)
        self.assertEqual(reported["FinalRecords"][0]["Status"], "0x8000000000000007")
        self.assertIsNone(reported["FinalRecords"][0]["ContainmentStatus"])
        self.assertIsNone(reported["FinalRecords"][0]["PciAvailableReported"])

    def test_unknown_saved_text_gets_explicit_partial_stage_and_preserved_hash(self):
        raw = b"Unrecognized PRIVATE data format\n\xffnot valid UTF-8"
        self.write("PRIVATE-unfamiliar.txt", raw)
        result = session.review(self.root)
        self.assertEqual(result["Status"], "reviewed", result)
        stage = result["Stages"][0]
        self.assertEqual((stage["Name"], stage["Status"], stage["Code"]),
                         ("saved_text", "partial", "unrecognized_text_format"))
        self.assertEqual(stage["Scope"], "saved_bytes_only")
        self.assertEqual(len(result["Observations"]), 1)
        self.assertEqual(result["Observations"][0]["Completion"], "partial")
        self.assertEqual(result["InputFiles"][0]["Sha256"], hashlib.sha256(raw).hexdigest())
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertEqual(result["NextAction"]["Code"], "review_existing_evidence")
        self.assert_scope(result)


if __name__ == "__main__":
    unittest.main()
