"""A test verifying that RunfilesGroupInfo returned by a *_binary target is valid.

Usage:

```starlark
load("@rules_runfiles_group//runfiles_group:runfiles_group_analysis_test.bzl", "runfiles_group_analysis_test")

runfiles_group_analysis_test(
    name = "test_runfiles_group_invariants",
    binaries = [
        ":my_binary",
        ":my_other_binary",
    ],
    overlapping_group_behavior = "error",
)
```
"""

load("@bazel_skylib//lib:sets.bzl", "sets")
load("//runfiles_group/private:lib.bzl", "lib")
load("//runfiles_group/private/providers:runfiles_group_info.bzl", "RunfilesGroupInfo")
load("//runfiles_group/private/providers:runfiles_group_metadata_info.bzl", "RunfilesGroupMetadataInfo")

_INDENT = "    "

def _indent(text):
    return "\n".join([_INDENT + line for line in text.split("\n")])

def _get_files(rf):
    return rf.files

def _get_empty_filenames(rf):
    return rf.empty_filenames

def _get_symlinks(rf):
    return rf.symlinks

def _get_root_symlinks(rf):
    return rf.root_symlinks

_RUNFILES_COMPONENTS = [
    ("files", _get_files),
    ("empty_filenames", _get_empty_filenames),
    ("symlinks", _get_symlinks),
    ("root_symlinks", _get_root_symlinks),
]

def _join_group_names(lighter_name, _lighter_weight, heavier_name, _heavier_weight):
    return lighter_name + "+" + heavier_name

def _make_join_group_names(prefix):
    def _join(lighter_name, _lighter_weight, heavier_name, _heavier_weight):
        stripped = heavier_name
        if stripped.startswith(prefix):
            stripped = stripped[len(prefix):]
        return lighter_name + "+" + stripped
    return _join

def _test_one(ctx, binary_attr):
    issues = []
    success = True
    default_info = binary_attr[DefaultInfo]
    default_runfiles = default_info.default_runfiles
    runfiles_group_info = binary_attr[RunfilesGroupInfo]
    if default_runfiles == None:
        return (False, ["doesn't have default_runfiles to compare to."])

    # Note: the following calculations are expensive.
    # This analysis test is only meant to be used to test the correctness of
    # RunfilesGroupInfo emitting rules. Do not use for all of your *_binary targets in prod.
    group_names = lib.group_names(runfiles_group_info)

    # Check completeness and overlap for each runfiles component.
    for component_name, get_depset in _RUNFILES_COMPONENTS:
        all_default = sets.make(get_depset(default_runfiles).to_list())
        all_grouped = sets.make()
        for gn in group_names:
            group_rf = getattr(runfiles_group_info, gn)
            for item in get_depset(group_rf).to_list():
                sets.insert(all_grouped, item)

        runfiles_match = sets.is_equal(all_default, all_grouped)
        if not runfiles_match:
            success = False
            missing_from_groups = sets.difference(all_default, all_grouped)
            extra_in_groups = sets.difference(all_grouped, all_default)
            if sets.length(missing_from_groups) > 0:
                issues.append(
                    "{} in default_runfiles missing from RunfilesGroupInfo:\n".format(component_name) +
                    "\n".join([_INDENT + str(item) for item in sets.to_list(missing_from_groups)]),
                )
            if sets.length(extra_in_groups) > 0:
                issues.append(
                    "{} in RunfilesGroupInfo missing from default_runfiles:\n".format(component_name) +
                    "\n".join([_INDENT + str(item) for item in sets.to_list(extra_in_groups)]),
                )

        if ctx.attr.overlapping_group_behavior != "ignore":
            for i in range(len(group_names)):
                group_i = sets.make(get_depset(getattr(runfiles_group_info, group_names[i])).to_list())
                for j in range(i + 1, len(group_names)):
                    group_j = sets.make(get_depset(getattr(runfiles_group_info, group_names[j])).to_list())
                    overlap = sets.intersection(group_i, group_j)
                    if sets.length(overlap) > 0:
                        msg = (
                            "{}: groups '{}' and '{}' overlap:\n".format(
                                component_name,
                                group_names[i],
                                group_names[j],
                            ) +
                            "\n".join([_INDENT + str(item) for item in sets.to_list(overlap)])
                        )
                        if ctx.attr.overlapping_group_behavior == "error":
                            success = False
                            issues.append(msg)
                        else:
                            # buildifier: disable=print
                            print("WARNING [{}]: {}".format(binary_attr.label, msg))

    # Apply the full resolution protocol (merge + ordering) and check expected group names.
    rgi = runfiles_group_info
    metadata = binary_attr[RunfilesGroupMetadataInfo] if RunfilesGroupMetadataInfo in binary_attr else None

    if ctx.attr.max_groups >= 0:
        join_fn = _make_join_group_names(ctx.attr.group_name_prefix) if ctx.attr.group_name_prefix else _join_group_names
        merged = lib.merge_to_limit(
            rgi,
            metadata,
            max_groups = ctx.attr.max_groups,
            merged_group_name = join_fn,
        )
        rgi = merged.runfiles_group_info
        metadata = merged.runfiles_group_metadata_info
        if ctx.attr.expected_group_count >= 0:
            if merged.group_count != ctx.attr.expected_group_count:
                success = False
                issues.append(
                    "expected {} groups after merging but got {}".format(
                        ctx.attr.expected_group_count,
                        merged.group_count,
                    ),
                )
        elif merged.group_count > ctx.attr.max_groups:
            success = False
            issues.append(
                "max_groups={} requested but merging could only reduce to {} groups".format(
                    ctx.attr.max_groups,
                    merged.group_count,
                ),
            )

    ordered = lib.ordered_groups(rgi, metadata)
    actual_names = [entry.name for entry in ordered]

    if ctx.attr.expected_group_names:
        if actual_names != ctx.attr.expected_group_names:
            success = False
            issues.append(
                "expected ordered group names:\n" +
                _INDENT + str(ctx.attr.expected_group_names) + "\n" +
                "actual ordered group names:\n" +
                _INDENT + str(actual_names),
            )

    executable_groups = [entry.name for entry in ordered if entry.metadata and entry.metadata.executable_group]
    if len(executable_groups) > 1:
        success = False
        issues.append(
            "at most one group may set executable_group = True, but found {}:\n".format(len(executable_groups)) +
            "\n".join([_INDENT + name for name in executable_groups]),
        )

    return (success, issues)

def _runfiles_group_analysis_test_impl(ctx):
    if len(ctx.attr.binaries) == 0:
        return [AnalysisTestResultInfo(
            success = False,
            message = "runfiles_group_analysis_test with no binaries.",
        )]

    results = []
    for binary_attr in ctx.attr.binaries:
        results.append((binary_attr.label, _test_one(ctx, binary_attr)))

    success = True
    sections = []
    for label, result in results:
        if not result[0]:
            success = False
            if len(result[1]) > 0:
                sections.append(
                    "Issues with {}:\n{}".format(
                        label,
                        "\n".join([_indent(issue) for issue in result[1]]),
                    ),
                )

    return [AnalysisTestResultInfo(
        success = success,
        message = "\n".join(sections),
    )]

runfiles_group_analysis_test = rule(
    implementation = _runfiles_group_analysis_test_impl,
    doc = """\
Checks that RunfilesGroupInfo is well formed by comparing all runfiles components
(files, empty_filenames, symlinks, root_symlinks) of DefaultInfo.default_runfiles
with the union of all runfiles from RunfilesGroupInfo.

Additionally, it can warn about entries appearing in multiple groups (overlapping),
verify the expected ordered group names after applying the full resolution protocol,
and optionally apply merge-to-limit before ordering.
""",
    attrs = {
        "binaries": attr.label_list(
            cfg = "target",
            mandatory = True,
            providers = [RunfilesGroupInfo],
            doc = "List of *_binary targets to test.",
        ),
        "overlapping_group_behavior": attr.string(
            doc = "How to handle overlapping groups (the same entry being present in more than one group).",
            default = "warn",
            values = ["warn", "ignore", "error"],
        ),
        "expected_group_names": attr.string_list(
            doc = """\
If set, the test verifies that the ordered group names (after optional merging and rank-based ordering)
match this list exactly. Applies to all binaries in the test.
""",
        ),
        "max_groups": attr.int(
            doc = "If >= 0, apply lib.merge_to_limit with this limit before ordering. -1 means no limit.",
            default = -1,
        ),
        "expected_group_count": attr.int(
            doc = """\
If >= 0, verify the exact number of groups after merging (requires max_groups >= 0).
Use this when merging cannot reach max_groups (e.g., due to do_not_merge or rank constraints)
to assert the actual reachable count. -1 means no check (the test fails if group_count > max_groups instead).
""",
            default = -1,
        ),
        "group_name_prefix": attr.string(
            doc = """\
If set, merged group names will strip this prefix from the second (heavier) group name
before joining with '+'. This avoids repeating a common prefix in merged names.
For example, with prefix "p#", merging "p#foo" and "p#bar" produces "p#foo+bar" instead of "p#foo+p#bar".
""",
        ),
    },
    analysis_test = True,
)
