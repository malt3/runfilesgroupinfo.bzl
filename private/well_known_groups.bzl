"""Defines well known groups of runfiles in the categorized runfiles info provider."""

# Runfiles from the same package needed at runtime.
# This is typically the main binary and any data files it needs.
# This is also considered the "default" category if no other, more specific category applies.
SAME_PARTY_RUNFILES = "SAME_PARTY_RUNFILES"

# Runfiles from third-party dependencies needed at runtime.
# These are typically shared libraries, interpreted code, or other resources
# that are not part of the same package as the target.
# This can be considered to be the default category for files provided by external repositories
# if no other, more specific category applies.
OTHER_PARTY_RUNFILES = "OTHER_PARTY_RUNFILES"

# Runfiles that are foundational to the application, e.g., interpreter or standard libraries.
# These can typically be shared across multiple applications.
# These often can be substituted by the runtime environment.
FOUNDATIONAL_RUNFILES = "FOUNDATIONAL_RUNFILES"

# Runfiles needed for debugging the application.
# These are typically not needed for normal operation, but can be useful for diagnosing issues.
# This can include external ELF files, DWARF files, source maps, or other external debug symbols.
DEBUG_RUNFILES = "DEBUG_RUNFILES"

# Runfiles needed for documentation.
# The application SHOULD still function without these files.
# Features that rely on these files MAY be disabled if they are not present,
# including help commands or man pages.
DOCUMENTATION_RUNFILES = "DOCUMENTATION_RUNFILES"
