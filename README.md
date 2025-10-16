# RunfilesGroupInfo provider

> This Bazel module contains a (work-in-progress) implementation of a grouped runfiles provider.

[See this proposal for more information](https://docs.google.com/document/d/1BOheluS2OOPfXyOMtbjnWvMivQo6CDjEB-_C-z3hBCg/edit).

It defines:

* `RunfilesGroupInfo` (the provider)
* A collection of well-known groups

## Intended use

The provider is intended to be added to `*_binary` rules and allows consumers of the binary to divide the set of runfiles into smaller subcomponents.


Consider the following example:

`foo_binary.bzl`:

```starlark
load("@runfilesgroupinfo.bzl", "RunfilesGroupInfo", "SAME_PARTY_RUNFILES", "OTHER_PARTY_RUNFILES", "FOUNDATIONAL_RUNFILES", "DEBUG_RUNFILES")

def _foo_binary_impl(ctx):
    # ... skipping over the rest of the logic

    # The runfiles contain all groups merged into one
    runfiles = ctx.runfiles(
        files = [main_file, interpreter_executable],
        transitive_files = [
            same_party_transitive,
            third_party_transitive,
            standard_library_data,
            language_runtime_data,
            sourcemaps,
            external_dwarf_symbols,
        ],
    )

    # RunfilesGroupInfo keeps different groups separated
    runfiles_group_info = RunfilesGroupInfo(
        SAME_PARTY_RUNFILES = depset([main_file], transitive = [same_party_transitive]),
        OTHER_PARTY_RUNFILES = depset(transitive = [third_party_transitive]),
        FOUNDATIONAL_RUNFILES = depset([interpreter_executable], transitive = [standard_library_data, language_runtime_data]),
        DEBUG_RUNFILES = depset(transitive = [sourcemaps, external_dwarf_symbols]),
    )

    # We return DefaultInfo and RunfilesGroupInfo.
    # This allows for the following use-cases:
    #  - consumers that cannot interpret RunfilesGroupInfo can simply ignore it and just use DefaultInfo (and the runfiles inside of it)
    #  - consumers that are aware of RunfilesGroupInfo can make informed decisions about splitting and filtering the different groups.
    #
    # Consumers that are aware of RunfilesGroupInfo can treat it as an optional provider. If it is not present, they can still fall back to the full set of runfiles from DefaultInfo.
    return [
        DefaultInfo(..., runfiles = runfiles),
        runfiles_group_info,
    ]

foo_binary = rule(
    implementation = _foo_binary_impl,
    # ... other arguments omitted
)
```

`custom_packaging_ruleset.bzl`:

```starlark
load("@runfilesgroupinfo.bzl", "RunfilesGroupInfo", "SAME_PARTY_RUNFILES", "OTHER_PARTY_RUNFILES", "FOUNDATIONAL_RUNFILES", "DEBUG_RUNFILES")

def _custom_package_impl(ctx):
    default_info = ctx.attr.binary[DefaultInfo]
    if RunfilesGroupInfo in ctx.attr.binary:
        # perform custom logic like splitting the third party deps into a separate layer
        # ... or maybe omit DEBUG_RUNFILES if compilation mode is not dbg
        runfiles_group_info = ctx.attr.binary[RunfilesGroupInfo]

        # use default_info.files together with some subset of runfiles_group_info
        return ...
    
    # if RunfilesGroupInfo is missing, we can still process the full set of runfiles as a fallback
    # do something with default_info.files and default_info.default_runfiles
    return ...
```