# Oracle Database 19c Software Packages

This tree contains platform-specific and generic software for building Oracle Database 19c Docker images.

## Layout

- `amd64/` - AMD64 platform folders, with `RU_*` subfolders and `base/`
- `arm64/` - ARM64 platform folders, with `RU_*` subfolders and `base/`
- `generic/` - Architecture-independent packages (e.g., DBRU generic zips)

Consolidated package lists live at the root as:
- `oracle_package_names_amd64_<RU>`
- `oracle_package_names_arm64_<RU>`