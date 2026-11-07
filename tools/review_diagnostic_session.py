"""One bounded, offline review of saved capture sets; never collects or unlocks.

Only trusted repository readers are imported. Captured files are immutable data
snapshots, never code. Child admission decisions are retained as observations;
a missing/partial/refused capture never requests another boot.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys
from types import SimpleNamespace

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = 1
MAX_FILES = 512
MAX_ENTRIES = 1024
MAX_DIRECTORIES = 128
MAX_DEPTH = 8
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_CAPTURES = 128
MAX_LINES = 100000
MAX_LINE_BYTES = 65536
REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
DIAG = re.compile(r"DIAG[0-9]{2}\.TXT", re.I)
IMAGE = re.compile(r"IMG[0-9]{2}\.BIN", re.I)
SHA256 = re.compile(r"[0-9a-f]{64}")
SOURCE_FILES = (
    "tools/review_diagnostic_session.py",
    "research/profile/check-compatibility.py",
    "research/profile/make-profile.py",
    "research/profile/capture_graph.py",
    "research/profile/gpu_path.py",
    "research/profile/summarize-graph.py",
    "research/profile/review-nvgop-code.py",
    "research/profile/review-edid-bindings.py",
    "research/profile/review-command-log.py",
    "research/profile/review-gop-records.py",
    "research/profile/proven.json",
)
OPTIONAL_READERS = frozenset(SOURCE_FILES[6:10])
CHILD_STATES = frozenset(("candidate", "needs_data", "outside_scope", "invalid_data", "error"))
GRAPH_KEYS = frozenset(("handle", "protocol", "opens", "open", "driver", "image", "gop", "pci", "path-node"))
SCOPE = {
    "Mode": "offline_saved_data",
    "CapturedCodeExecuted": False,
    "HardwareAccess": False,
    "ProfileGenerated": False,
    "FirmwareOrSettingsChanged": False,
    "NewCaptureRequested": False,
    "DriverReleaseVerified": False,
    "WindowsRecoveryVerified": False,
}


class InputProblem(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


class ToolProblem(ValueError):
    pass


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=True).encode("ascii")).hexdigest()


def _linked(info):
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & REPARSE_POINT)


def _signature(info):
    # Windows lstat/fstat can expose different creation/change-time semantics.
    # Identity, size and mtime plus the final full digest are the portable checks.
    return (info.st_mode, info.st_size, info.st_mtime_ns,
            info.st_dev, info.st_ino, getattr(info, "st_file_attributes", 0))


def _plain_root(folder):
    path = Path(os.path.abspath(os.fspath(folder)))
    # Checking the leaf alone misses a junction/symlink in an ancestor.
    for current in reversed((path, *path.parents)):
        info = current.lstat()
        if _linked(info):
            raise InputProblem("linked_path_refused")
    if not stat.S_ISDIR(path.lstat().st_mode):
        raise InputProblem("input_not_directory")
    return path


def _read_regular(path, expected, limit):
    _plain_root(path.parent)
    if _linked(expected) or not stat.S_ISREG(expected.st_mode):
        raise InputProblem("non_regular_input_refused")
    if expected.st_size > limit:
        raise InputProblem("input_size_limit")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        if _linked(before) or not stat.S_ISREG(before.st_mode) or _signature(before) != _signature(expected):
            raise InputProblem("input_changed")
        data = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    final = path.lstat()
    _plain_root(path.parent)
    if len(data) > limit:
        raise InputProblem("input_size_limit")
    if _linked(final) or _signature(before) != _signature(after) or _signature(after) != _signature(final):
        raise InputProblem("input_changed")
    return data


def _kind(name):
    if DIAG.fullmatch(name):
        return "diagnostic"
    if IMAGE.fullmatch(name):
        return "image"
    if name.upper() == "PROM.BIN":
        return "prom"
    return "other"


class Snapshot:
    def __init__(self, root, files):
        self.root = root
        self.files = files
        manifest = [{"path": "/".join(key), "bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()}
                    for key, data in sorted(files.items())]
        self.digest = _digest({"format": 1, "files": manifest})
        self.ids = {key: "file%04d" % (index + 1) for index, key in enumerate(sorted(files))}
        self.public = []
        for key in sorted(files):
            data = files[key]
            row = {"Id": self.ids[key], "Kind": _kind(key[-1]), "Bytes": len(data),
                   "Sha256": hashlib.sha256(data).hexdigest()}
            # Never export arbitrary filenames or directory names.
            if row["Kind"] != "other":
                row["Name"] = key[-1].upper()
            self.public.append(row)


def snapshot(folder):
    root = _plain_root(folder)
    pending = [(root, (), 0)]
    files = {}
    directory_count = entry_count = total = 0
    while pending:
        directory, relative, depth = pending.pop()
        directory_count += 1
        if directory_count > MAX_DIRECTORIES:
            raise InputProblem("input_directory_limit")
        info = directory.lstat()
        if _linked(info) or not stat.S_ISDIR(info.st_mode):
            raise InputProblem("linked_path_refused")
        entries = []
        with os.scandir(directory) as listing:
            for entry in listing:
                entry_count += 1
                if entry_count > MAX_ENTRIES:
                    raise InputProblem("input_entry_limit")
                entries.append(entry)
        names = set()
        for entry in sorted(entries, key=lambda item: (item.name.casefold(), item.name)):
            folded = entry.name.casefold()
            if folded in names:
                raise InputProblem("ambiguous_file_names")
            names.add(folded)
            path = directory / entry.name
            child = path.lstat()
            if _linked(child):
                raise InputProblem("linked_path_refused")
            key = (*relative, entry.name)
            if stat.S_ISDIR(child.st_mode):
                if depth >= MAX_DEPTH:
                    raise InputProblem("input_depth_limit")
                pending.append((path, key, depth + 1))
            elif stat.S_ISREG(child.st_mode):
                if len(files) >= MAX_FILES:
                    raise InputProblem("input_file_limit")
                data = _read_regular(path, child, min(MAX_FILE_BYTES, MAX_TOTAL_BYTES - total))
                total += len(data)
                files[key] = data
            else:
                raise InputProblem("non_regular_input_refused")
    return Snapshot(root, files)


def _source_manifest(repo):
    root = _plain_root(repo)
    rows = []
    for name in SOURCE_FILES:
        path = root.joinpath(*name.split("/"))
        try:
            # Also check source subdirectory ancestry before any import.
            _plain_root(path.parent)
            data = _read_regular(path, path.lstat(), 2 * 1024 * 1024)
        except FileNotFoundError:
            if name not in OPTIONAL_READERS:
                raise ToolProblem("required_reader_missing") from None
            rows.append({"name": name, "missing": True})
        else:
            rows.append({"name": name, "sha256": hashlib.sha256(data).hexdigest()})
    return _digest({"sources": rows, "python": list(sys.version_info[:3])})


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Readers:
    def __init__(self, repo=REPO):
        folder = Path(repo) / "research" / "profile"
        self.checker = _load("session_compatibility", folder / "check-compatibility.py")
        self.graph = _load("session_graph", folder / "summarize-graph.py")
        self.nvgop = (_load("session_nvgop", folder / "review-nvgop-code.py")
                      if (folder / "review-nvgop-code.py").is_file() else None)
        self.edid = (_load("session_edid", folder / "review-edid-bindings.py")
                     if (folder / "review-edid-bindings.py").is_file() else None)
        self.command = (_load("session_command", folder / "review-command-log.py")
                        if (folder / "review-command-log.py").is_file() else None)
        self.gop = (_load("session_gop_records", folder / "review-gop-records.py")
                    if (folder / "review-gop-records.py").is_file() else None)
        self.envelope = json.loads((folder / "proven.json").read_text(encoding="utf-8"))
        self.checker.validate_envelope(self.envelope)


class MemoryFile:
    def __init__(self, name, data=None):
        self.name, self.data = name, data

    def read_bytes(self):
        if self.data is None:
            raise FileNotFoundError()
        return self.data

    def is_file(self):
        return self.data is not None

    def is_symlink(self):
        return False

    def stat(self):
        return SimpleNamespace(st_size=len(self.read_bytes()), st_mode=stat.S_IFREG)


class MemoryFolder:
    """Path-like view containing only immutable files from one captured folder."""
    def __init__(self, files):
        self.files = {name.upper(): data for name, data in files.items()}

    def is_dir(self):
        return True

    def is_symlink(self):
        return False

    def iterdir(self):
        return iter(MemoryFile(name, data) for name, data in sorted(self.files.items()))

    def __truediv__(self, name):
        if not isinstance(name, str) or "/" in name or "\\" in name or name in (".", ".."):
            raise FileNotFoundError()
        return MemoryFile(name.upper(), self.files.get(name.upper()))


class MemoryInputs:
    """Preserve the existing checker's own per-file and total-read limits."""
    def __init__(self, checker, folder):
        self.checker, self.folder, self.cache, self.total = checker, folder, {}, 0

    def read(self, name, limit):
        if name not in self.cache:
            row = self.folder / name
            data = row.read_bytes()
            if len(data) > limit or self.total + len(data) > self.checker.TOTAL_LIMIT:
                raise self.checker.InputLimit()
            self.total += len(data)
            self.cache[name] = row
        return self.cache[name]

    def __truediv__(self, name):
        if not re.fullmatch(r"IMG[0-9]{2,20}\.BIN", name):
            raise self.checker.InputLimit()
        return self.read(name, self.checker.mp.IMAGE_MAX)


def _number(value, maximum=0xffffffff):
    return value if type(value) is int and 0 <= value <= maximum else None


def _safe_hash(value):
    return value if isinstance(value, str) and SHA256.fullmatch(value) else None


def _decode_text(data):
    text = data.decode("utf-8-sig").replace("\r\n", "\n")
    lines = text.splitlines()
    if len(lines) > MAX_LINES or any(len(line) > MAX_LINE_BYTES for line in lines):
        raise ValueError("text bounds")
    return text


def _graph_observation(data, file_id, readers):
    text = _decode_text(data)
    lines = text.splitlines()
    raw = readers.graph.summarize(data)
    counts = {key: 0 for key in sorted(GRAPH_KEYS)}
    for record in raw["records"]:
        key = record.split(" ", 1)[0]
        if key in counts:
            counts[key] += 1
    identities = set()
    # These are observed PCI header identities, not a claim of complete inventory.
    for line in lines:
        match = re.fullmatch(r"pci config-dwords=((?:[0-9a-f]{8} ){15}[0-9a-f]{8}) ?", line)
        if match:
            words = [int(word, 16) for word in match[1].split()]
            if words[2] >> 24 == 3:
                identities.add((words[0] & 0xffff, words[0] >> 16, words[11], words[2]))
    allowed_reasons = set(readers.graph.REASONS) | {
        "probe-unreviewed-envelope", "probe-identity-changed",
    }
    reasons = []
    reason_count = 0
    for line in lines:
        if line.startswith("incomplete reason="):
            reason_count += 1
            match = re.fullmatch(r"incomplete reason=([a-z-]+) status=(0x[0-9a-f]{16})", line)
            if match and match[1] in allowed_reasons and len(reasons) < 64:
                reasons.append({"Code": match[1], "Status": match[2]})
    complete = raw["complete_markers"]
    statuses = raw["diagnostic_statuses"]
    # Do not turn missing/malformed/duplicate footer observations into success.
    complete_lines = [line for line in lines if line.startswith("capture-complete=")]
    status_lines = [line for line in lines if line.startswith("diagnostic-result status=")]
    if (complete_lines == ["capture-complete=1"] and
            status_lines == ["diagnostic-result status=0x0000000000000000"] and not reason_count):
        completion = "complete_markers"
    elif len(complete_lines) > 1 or len(status_lines) > 1:
        completion = "ambiguous_markers"
    elif "0" in complete or reason_count or any(int(value, 16) for value in statuses):
        completion = "incomplete"
    else:
        completion = "partial_or_unrecognized"
    graph_only = raw["graph_only_marker"]
    deep = bool(re.search(r"^(?:probe-target |mmio off=|prom sha256=|cfg dwords=)", text, re.M))
    return text, {
        "FileId": file_id,
        "Layout": "graph_only" if graph_only else "deep_probe" if deep else "diagnostic",
        "Completion": completion,
        "CompletionMarkers": [int(value) for value in complete[:16]],
        "DiagnosticStatuses": statuses[:16],
        "FooterObservationsTruncated": len(complete) > 16 or len(statuses) > 16,
        "GraphRecordCounts": counts,
        "DisplayIdentityObservations": [
            {"Vendor": "%04x" % vendor, "Device": "%04x" % device,
             "Subsystem": "%08x" % subsystem, "ClassRevision": "%08x" % revision}
            for vendor, device, subsystem, revision in sorted(identities)[:32]
        ],
        "DisplayIdentityObservationsTruncated": len(identities) > 32,
        "IncompleteReasonCount": reason_count,
        "IncompleteReasons": reasons,
        "UnexportedReasonCount": reason_count - len(reasons),
        "Scope": "observed_saved_metadata_not_ownership_verification",
    }


def _compatibility_stage(folder, captures, readers, set_id):
    checker = readers.checker
    result = checker.check(folder, readers.envelope, inputs=MemoryInputs(checker, folder))
    state = result.get("status")
    if state not in CHILD_STATES:
        raise ToolProblem("invalid_checker_result")
    checks = []
    for row in result.get("checks", [])[:256]:
        code = row.get("code")
        checks.append({
            "State": row.get("state") if row.get("state") in CHILD_STATES else "error",
            "Code": code if code in checker.MESSAGES else "unrecognized_checker_result",
            "FileId": captures.get(row.get("capture")),
        })
    return {"Name": "compatibility", "SetId": set_id, "Status": state,
            "CheckerVersion": _number(result.get("checker_version")),
            "Checks": checks, "Scope": "unchanged_strict_automatic_profile_checks"}


def _nvgop_stage(text, folder, readers, file_id):
    stage = {"Name": "nvgop_code", "FileId": file_id, "Scope": "saved_code_identity_only",
             "code_only": True, "hardware_verified": False,
             "driver_release_verified": False, "write_eligible": False}
    if readers.nvgop is None:
        return dict(stage, Status="unavailable", Code="reader_unavailable")
    if not any(IMAGE.fullmatch(name) for name in folder.files):
        return dict(stage, Status="unavailable", Code="saved_images_not_present")
    try:
        row = readers.nvgop.review(text, folder, readers.envelope)
    except (ValueError, KeyError, TypeError, OSError):
        return dict(stage, Status="unavailable", Code="saved_nvgop_not_uniquely_reviewable")
    values = {"Version": row.get("version"),
              "ImageSha256": _safe_hash(row.get("image_sha256")),
              "CodeSha256": _safe_hash(row.get("code_sha256"))}
    if not isinstance(values["Version"], str) or not re.fullmatch(r"[0-9a-f]{1,8}", values["Version"]):
        raise ToolProblem("invalid_code_result")
    for source, destination in (("image_bytes", "ImageBytes"), ("code_rva", "CodeRva"),
                                ("code_bytes", "CodeBytes"), ("stop_rva", "StopRva")):
        values[destination] = _number(row.get(source), MAX_FILE_BYTES)
    matches = []
    for match in row.get("matching_family_code_entries", [])[:16]:
        family, chip = match.get("family"), match.get("chip")
        if (isinstance(family, str) and re.fullmatch(r"[A-Za-z0-9_]{1,24}", family) and
                isinstance(chip, str) and re.fullmatch(r"[0-9a-f]{8}", chip)):
            matches.append({"Family": family, "Chip": chip})
    return dict(stage, Status="observed", FamilyCodeMatches=matches, **values)


def _edid_stage(text, readers, file_id):
    stage = {"Name": "edid_bindings", "FileId": file_id,
             "Scope": "saved_binding_identity_only", "no_edid_driver_authorized": False,
             "driver_detach_authorized": False, "post_release_binding_verified": False}
    if readers.edid is None:
        return dict(stage, Status="unavailable", Code="reader_unavailable")
    try:
        row = readers.edid.review(text)
    except (ValueError, KeyError, TypeError, OSError):
        return dict(stage, Status="unavailable", Code="complete_binding_graph_unavailable")
    owners = []
    for owner in row.get("bindings", [])[:32]:
        protocol = owner.get("protocol")
        if protocol not in ("active", "discovered"):
            raise ToolProblem("invalid_binding_result")
        identity = owner.get("file_guid")
        owners.append({"Protocol": protocol, "Version": _number(owner.get("version")),
                       "ReviewedMouseIdentityMatch": owner.get("reviewed_mouse_identity_match") is True,
                       "OwnerIdentitySha256": hashlib.sha256(identity.encode("ascii")).hexdigest()
                       if isinstance(identity, str) and re.fullmatch(r"[0-9a-f-]{36}", identity) else None})
    return dict(stage, Status="observed", Bindings=owners,
                BindingsTruncated=len(row.get("bindings", [])) > 32,
                DiscoveredByDriverCount=_number(row.get("discovered_by_driver_count"), 100000),
                ActiveByDriverCount=_number(row.get("active_by_driver_count"), 100000))


def _text_readers(name, data):
    if Path(name).suffix.casefold() not in (".txt", ".log"):
        return ()
    # Inspect ASCII markers before decoding, so a damaged recognized log still
    # gets an explicit observation instead of vanishing from the report.
    raw = data[3:] if data.startswith(b"\xef\xbb\xbf") else data
    kinds = []
    if re.search(rb"^(?:\[Decode\]|Transaction result=)", raw, re.M):
        kinds.append("command")
    if re.search(rb"^GOPDIAG", raw, re.M):
        kinds.append("gop")
    if re.search(rb"^(?:transaction result=|FINAL |GOP\[)", raw, re.M):
        kinds.append("wrapper")
    if not kinds and not DIAG.fullmatch(name):
        kinds.append("unrecognized")
    return tuple(kinds)


def _observed_integer(value, minimum=0, maximum=0xffffffff):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError("bounded integer required")
    return value


def _observed_boolean(value):
    if type(value) is not bool:
        raise ValueError("boolean required")
    return value


def _command_values(row, text):
    before = _observed_integer(row["decode_before"], maximum=0xffff)
    after = _observed_integer(row["decode_after"], maximum=0xffff)
    transaction = row["transaction"]
    values = {"Result": _observed_integer(transaction["result"], -(2 ** 63), 2 ** 63 - 1),
              "DmaLive": _observed_integer(transaction["dma_live"], maximum=10000000)}
    for source, destination in (("safe", "Safe"), ("retained", "Retained"),
                                ("started", "Started"), ("quiesced", "Quiesced"),
                                ("flrs", "Flrs")):
        values[destination] = _observed_integer(transaction[source], maximum=1) == 1
    restore = row["restore"]
    if restore is not None:
        restore = {destination: _observed_integer(restore[source], maximum=0xffff)
                   for source, destination in (("actual", "Actual"),
                                               ("transaction_original", "TransactionOriginal"),
                                               ("mask", "Mask"))}
    # The child reader rejects malformed required records. Also preserve extra
    # recognized markers that its exact record expressions did not consume.
    marker_count = len(re.findall(r"^(?:\[Decode\]|Transaction result=)", text, re.M))
    restore_marker_count = len(re.findall(r"^restore PCI command:", text, re.M))
    fully_reviewed = marker_count == 3 and restore_marker_count == int(restore is not None)
    return {"Status": "observed" if fully_reviewed else "partial",
            "Code": "command_records_observed" if fully_reviewed else "command_markers_not_fully_reviewed",
            "MarkerLineCount": marker_count, "RestoreMarkerLineCount": restore_marker_count,
            "DecodeBefore": before, "DecodeAfter": after, "Transaction": values,
            "Restore": restore,
            "TransactionOriginalDiffersFromWrapperEntry":
                restore["TransactionOriginal"] != before if restore is not None else None,
            "WrapperEntryRestorationVerified": False}


def _gop_values(row, text):
    source_rows = row["observations"]
    if not isinstance(source_rows, list) or not 1 <= len(source_rows) <= 128:
        raise ValueError("bounded observations required")
    phases, observations = {}, []
    classifications = {"present-without-framebuffer", "partial-framebuffer", "framebuffer-recorded"}
    for source in source_rows:
        phase = source["phase"]
        if not isinstance(phase, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,32}", phase):
            raise ValueError("bounded phase required")
        phases.setdefault(phase, "phase%04d" % (len(phases) + 1))
        classification = source["classification"]
        if classification not in classifications:
            raise ValueError("unknown GOP classification")
        observations.append({
            "PhaseId": phases[phase],
            "Index": _observed_integer(source["index"], maximum=127),
            "TargetReported": _observed_boolean(source["target_reported"]),
            "ModeIndexInRange": _observed_boolean(source["mode_index_in_range"]),
            "FramebufferAbsent": _observed_boolean(source["framebuffer_absent"]),
            "FramebufferPartial": _observed_boolean(source["framebuffer_partial"]),
            "Width": _observed_integer(source["width"]),
            "Height": _observed_integer(source["height"]),
            "Classification": classification,
        })
    marker_count = len(re.findall(r"^GOPDIAG", text, re.M))
    return {"Status": "observed" if marker_count == len(observations) else "partial",
            "Code": "gop_records_observed" if marker_count == len(observations) else "gop_markers_not_fully_reviewed",
            "MarkerLineCount": marker_count, "Records": observations,
            "AncestryIndependentlyVerified": False, "FramebufferGeometryVerified": False,
            "SetModeAuthorized": False, "ConnectControllerAuthorized": False}


def _legacy_wrapper_values(text):
    """Project a few recorded legacy fields, without interpreting readiness."""
    def integer(value, maximum=0xffffffff):
        return _observed_integer(int(value, 0) if value.startswith("0x") else int(value),
                                 maximum=maximum)

    def status(value):
        return "0x%016x" % integer(value, 0xffffffffffffffff)

    def signed(value):
        return _observed_integer(int(value), -(2 ** 63), 2 ** 63 - 1)

    def flag(value):
        return integer(value, 1) == 1

    def transaction(values):
        result, containment, started, quiesced, fault, retained, maps, flrs = values
        return {"Result": signed(result), "ContainmentStatus": status(containment),
                "Started": flag(started), "Quiesced": flag(quiesced), "Fault": integer(fault),
                "Retained": flag(retained), "Maps": integer(maps, 10000000),
                "Flrs": integer(flrs, 10000000)}

    def containment(values):
        attribute, hardware, command, cached, pending = values
        return {"AttributeStatus": status(attribute), "HardwareStatus": status(hardware),
                "ReportedCommand": integer(command, 0xffff),
                "LoggedCachedAttributes": status(cached), "Pending": flag(pending)}

    def final(values):
        result, phase, attempted, released, clean, containment_result, pci = values
        return {"Status": status(result),
                "Phase": phase if phase == "post-unlock-handoff" else "unclassified_phase",
                "PhaseSha256": hashlib.sha256(phase.encode("ascii")).hexdigest(),
                "Attempted": flag(attempted), "DriverReleaseReported": flag(released),
                "CleanReported": flag(clean),
                "ContainmentStatus": status(containment_result) if containment_result is not None else None,
                "PciAvailableReported": flag(pci) if pci is not None else None}

    number = r"(0x[0-9a-f]{1,16}|[0-9]{1,20})"
    specifications = (
        ("TransactionRecords", "transaction result=",
         r"transaction result=(-?[0-9]{1,20}) containment=" + number +
         r" started=([01]) quiesced=([01]) fault=([0-9]{1,20}) retained=([01]) maps=([0-9]{1,20}) FLR=([0-9]{1,20})",
         transaction),
        ("ContainmentRecords", "BME containment:",
         r"BME containment: attribute_status=" + number + r" hardware_status=" + number +
         r" command=" + number + r" cached=" + number + r" pending=([01])", containment),
        ("FinalRecords", "FINAL ",
         r"FINAL status=" + number + r" stage=([A-Za-z0-9_.-]{1,64}) attempted=([01]) driver_release=([01]) clean=([01])(?: containment=" + number + r" pci_available=([01]))?",
         final),
        ("SetModeRecords", "GOP SetMode",
         r"GOP SetMode status=" + number, lambda values: {"Status": status(values[0])}),
        ("RestoreRecords", "restore PCI command:",
         r"restore PCI command: actual=" + number + r" original=" + number + r" mask=" + number,
         lambda values: dict(zip(("Actual", "TransactionOriginal", "Mask"),
                                (integer(value, 0xffff) for value in values)))),
    )
    records = {name: [] for name, *_ in specifications}
    marker_counts = {name: 0 for name in records}
    malformed = truncated = 0
    for sequence, line in enumerate(text.splitlines(), 1):
        for name, prefix, pattern, convert in specifications:
            if not line.startswith(prefix):
                continue
            marker_counts[name] += 1
            match = re.fullmatch(pattern, line)
            try:
                if match is None:
                    raise ValueError("unreviewed record")
                row = convert(match.groups())
            except (ValueError, TypeError, OverflowError):
                malformed += 1
                continue
            if len(records[name]) < 32:
                records[name].append(dict(Sequence=sequence, **row))
            else:
                truncated += 1
    # The wrapper contains additional code/configuration/ownership details this
    # projection does not validate. Even all-zero records remain partial evidence.
    return {"Status": "partial", "Code": "legacy_wrapper_observations_only",
            "MarkerCounts": marker_counts, "MalformedRecordCount": malformed,
            "TruncatedRecordCount": truncated,
            "GopIndexMarkerCount": len(re.findall(r"^GOP\[", text, re.M)),
            "WrapperEntryRestorationVerified": False, "CacheConsistencyVerified": False,
            "WindowsRecoveryVerified": False, "UnlockVerified": False, **records}


def _saved_text_stage(kind, data, readers, file_id):
    names = {"command": "command_boundaries", "gop": "gop_records",
             "wrapper": "legacy_wrapper", "unrecognized": "saved_text"}
    stage = {"Name": names[kind],
             "FileId": file_id, "Scope": "recorded_text_values_only",
             "hardware_independently_verified": False, "write_eligible": False}
    if kind == "unrecognized":
        return dict(stage, Status="partial", Code="unrecognized_text_format", Scope="saved_bytes_only")
    if kind == "wrapper":
        try:
            text = _decode_text(data)
            values = _legacy_wrapper_values(text)
        except (UnicodeError, ValueError, TypeError, OverflowError):
            return dict(stage, Status="partial", Code="wrapper_text_not_reviewable")
        return dict(stage, NormalizedTextSha256=hashlib.sha256(text.encode("utf-8")).hexdigest(), **values)
    reader = getattr(readers, kind)
    if reader is None:
        return dict(stage, Status="unavailable", Code="reader_unavailable")
    try:
        text = _decode_text(data)
        row = reader.review(text)
        values = _command_values(row, text) if kind == "command" else _gop_values(row, text)
    except (UnicodeError, ValueError, KeyError, TypeError, OSError, OverflowError):
        return dict(stage, Status="partial", Code=kind + "_records_partial_or_invalid")
    return dict(stage, NormalizedTextSha256=hashlib.sha256(text.encode("utf-8")).hexdigest(), **values)


def analyze_snapshot(saved, readers):
    groups = {}
    capture_count = sum(_kind(key[-1]) == "diagnostic" or bool(_text_readers(key[-1], data))
                        for key, data in saved.files.items())
    if capture_count > MAX_CAPTURES:
        raise InputProblem("input_capture_limit")
    for key, data in sorted(saved.files.items()):
        groups.setdefault(key[:-1], {})[key[-1]] = data
    stages, observations = [], []
    for index, (parent, files) in enumerate(sorted(groups.items()), 1):
        set_id = "set%04d" % index
        for name in sorted(files):
            for kind in _text_readers(name, files[name]):
                file_id = saved.ids[(*parent, name)]
                stage = _saved_text_stage(kind, files[name], readers, file_id)
                stages.append(stage)
                observations.append({"FileId": file_id, "SetId": set_id,
                                     "Layout": "saved_" + kind + "_log",
                                     "Completion": "observed" if stage["Status"] == "observed" else "partial",
                                     "Scope": "recorded_text_values_only"})
        diagnostics = [name for name in sorted(files) if DIAG.fullmatch(name)]
        if not diagnostics:
            continue
        full_folder = MemoryFolder(files)
        compatibility_files = {name: data for name, data in files.items() if not DIAG.fullmatch(name)}
        capture_ids = {}
        unreviewable = []
        for name in diagnostics:
            file_id = saved.ids[(*parent, name)]
            try:
                text, observation = _graph_observation(files[name], file_id, readers)
            except (UnicodeError, ValueError):
                unreviewable.append(file_id)
                observations.append({"FileId": file_id, "SetId": set_id,
                                     "Completion": "unreadable_text",
                                     "Scope": "saved_bytes_only"})
                stages.append({"Name": "graph_metadata", "FileId": file_id,
                               "Status": "unavailable", "Code": "text_not_reviewable"})
                continue
            observation["SetId"] = set_id
            observations.append(observation)
            stages.append({"Name": "graph_metadata", "FileId": file_id,
                           "Status": "observed", "Scope": "saved_metadata_only"})
            stages.append(_edid_stage(text, readers, file_id))
            stages.append(_nvgop_stage(text, full_folder, readers, file_id))
            if observation["Layout"] != "graph_only":
                compatibility_files[name] = files[name]
                capture_ids[name.upper()] = file_id
        if unreviewable:
            # A corrupt/oversized textual record cannot disappear while the
            # remaining records are presented as an adequate capture set.
            stages.append({"Name": "compatibility", "SetId": set_id, "Status": "invalid_data",
                           "Checks": [{"State": "invalid_data", "Code": "observations_invalid", "FileId": value}
                                      for value in unreviewable],
                           "Scope": "strict_check_not_bypassed_for_unreviewable_capture"})
        elif capture_ids:
            stages.append(_compatibility_stage(MemoryFolder(compatibility_files), capture_ids, readers, set_id))
        else:
            stages.append({"Name": "compatibility", "SetId": set_id, "Status": "not_applicable",
                           "Code": "no_deep_capture_in_set",
                           "Scope": "unchanged_strict_automatic_profile_checks"})
    return stages, observations


def _base_report():
    return {"SchemaVersion": SCHEMA_VERSION, "Test": "diagnostic-session-review-v1",
            "Status": "reviewed", "Unchanged": False, "CacheReusable": False, "InputDigest": None,
            "AnalyzerDigest": None, "CacheKey": None, "InputFiles": [],
            "Stages": [], "Observations": [], "Scope": dict(SCOPE),
            "hardware_tested": False, "write_eligible": False}


def review(folder, *, previous_cache_key=None, repo=REPO):
    result = _base_report()
    try:
        try:
            source_digest = _source_manifest(repo)
        except (InputProblem, OSError, UnicodeError):
            raise ToolProblem("reader_source_unavailable") from None
        saved = snapshot(folder)
        key = _digest({"schema": SCHEMA_VERSION, "input": saved.digest, "analyzer": source_digest})
        result.update(InputDigest=saved.digest, AnalyzerDigest=source_digest,
                      CacheKey=key, InputFiles=saved.public)
        if previous_cache_key is not None and not SHA256.fullmatch(previous_cache_key):
            raise InputProblem("invalid_previous_cache_key")
        if previous_cache_key == key:
            result["Unchanged"] = True
        else:
            try:
                readers = Readers(repo)
            except Exception:
                raise ToolProblem("reader_installation_invalid") from None
            result["Stages"], result["Observations"] = analyze_snapshot(saved, readers)
        # Recheck bytes and file membership after readers run (or before cache reuse).
        # Parsers never reread the live folder; their input was the immutable snapshot.
        if snapshot(folder).digest != saved.digest:
            raise InputProblem("input_changed")
        try:
            final_source_digest = _source_manifest(repo)
        except (InputProblem, OSError, UnicodeError):
            raise ToolProblem("reader_source_changed") from None
        if final_source_digest != source_digest:
            raise ToolProblem("reader_source_changed")
        result["CacheReusable"] = True
        if result["Unchanged"]:
            result["NextAction"] = {"Code": "reuse_existing_analysis",
                                    "Message": "Input and analyzer hashes are unchanged; retain the previous reviewed report."}
        elif result["Observations"]:
            result["NextAction"] = {"Code": "review_existing_evidence",
                                    "Message": "Review the saved observations and remaining source questions. No repeat capture, profile generation or boot is requested."}
        else:
            result["NextAction"] = {"Code": "review_input_folder",
                                    "Message": "No recognizable saved DIAG, command or GOP log records were found. Review the existing folder selection; a new capture is not requested."}
        return result
    except InputProblem as error:
        code = error.code
    except (OSError, UnicodeError):
        code = "input_unreadable"
    except Exception:
        # No parser exception text, file paths or captured bytes cross this boundary.
        result.update(Status="tool_error", CacheReusable=False, Unchanged=False)
        result["CacheKey"] = _digest({"error_domain": 1, "status": "tool_error",
                                      "input": result["InputDigest"], "analyzer": result["AnalyzerDigest"]})
        result["Stages"].append({"Name": "analyzer_validation", "Status": "error", "Code": "reader_error"})
        result["NextAction"] = {"Code": "review_analyzer_installation",
                                "Message": "The offline readers could not finish. Preserve the existing files; no hardware action is requested."}
        return result
    result.update(Status="input_refused", CacheReusable=False, Unchanged=False)
    result["CacheKey"] = _digest({"error_domain": 1, "status": "input_refused", "code": code,
                                  "input": result["InputDigest"], "analyzer": result["AnalyzerDigest"]})
    result["Stages"].append({"Name": "input_validation", "Status": "refused", "Code": code})
    result["NextAction"] = {"Code": "review_existing_input",
                            "Message": "The input was unreadable, changed, linked or exceeded a bound. Preserve it and review the local folder; do not collect again."}
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", type=Path)
    parser.add_argument("--previous-cache-key")
    args = parser.parse_args(argv)
    result = review(args.captures, previous_cache_key=args.previous_cache_key)
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2))
    return {"reviewed": 0, "input_refused": 2, "tool_error": 3}[result["Status"]]


if __name__ == "__main__":
    sys.exit(main())
