"""Defines provider for grouping runfiles into different subcategories.

This is essentially a special-purpose version of OutputGroupInfo.
If present, it can be used instead of DefaultInfo.default_runfiles."""

_DOC = """\
Information about grouped runfiles.

Each field in this provider is a runfiles object, representing a category of runfiles.
Merging all runfiles objects from all fields must yield the same runfiles as DefaultInfo.default_runfiles.

This provider functions similarly to OutputGroupInfo, but its presence in the output of a rule indicates that it can be used instead of DefaultInfo.default_runfiles.
It categorizes the runfiles of a target into different groups, allowing for more fine-grained control over which runfiles are used in different contexts.
"""

def _make_runfilesgroupinfo_init(**kwargs):
    # Once Starlark supports type checking,
    # we should ensure that all fields are runfiles objects.
    # For now, we just hope and pray.
    return kwargs

RunfilesGroupInfo, _ = provider(
    doc = _DOC,
    init = _make_runfilesgroupinfo_init,
)
