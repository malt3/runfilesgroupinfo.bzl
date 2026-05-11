"""Computed group names that vary across Bazel versions."""

def _repo_name(label_str):
    """Extracts the canonical repo name from a stringified Label."""
    # Label format: "@@<repo_name>//<package>:<target>"
    return label_str.split("//")[0].removeprefix("@@").removeprefix("@")

IRS_F1040 = _repo_name(str(Label("@irs_f1040//file")))
