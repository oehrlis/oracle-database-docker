# Oracle Database Docker Images

This repository provides a modular and maintainable framework for building **multi-platform Oracle Database Docker images**, including support for:

- Multiple Oracle Database versions (e.g. 19c, 23ai)
- Release Updates (RUs) with patch ZIP management
- `amd64` and `arm64` architectures
- Docker Compose setups for local development and testing

> ⚠️ This is a **community-maintained project** by [OraDBA](https://www.oradba.ch)  
> It is **not affiliated with Oracle Corporation**.  
> For official Oracle container builds, see [oracle/docker-images](https://github.com/oracle/docker-images)

## Repository Structure

```text
.
├── bin/                    # Build scripts and project tooling
│   ├── buildDB.sh          # Main image build script
│   └── template.sh         # Script templates or test helpers

├── common/                 # Shared Docker logic and shell utilities
│   ├── docker/             # Reusable Dockerfile snippets
│   └── scripts/            # Common shell functions

├── database/               # Oracle Database build definitions
│   ├── 19/                 # Oracle 19c
│   │   ├── docker/         # Base Dockerfile templates
│   │   ├── config/         # Setup/startup scripts
│   │   └── software/       # Patch ZIPs and metadata
│   ├── 23/                 # Oracle 23ai
│   └── README.md           # Supported versions and build notes

├── doc/                    # Markdown documentation
│   ├── usage.md
│   ├── patching.md
│   └── build_matrix.md

├── artefacts/              # Output logs or build metadata
├── images/                 # Logos and visual assets
├── notes/                  # Changelogs or internal notes

├── .gitignore
├── LICENSE
└── README.md               # This file
````

## Features

- ✅ Support for Oracle 19c and 23ai builds
- ✅ Multi-platform: `amd64` and `arm64`
- ✅ Per-RU patch ZIP management
- ✅ Modular build logic for reuse and automation
- ✅ Docker Compose support for common use cases
- ✅ Clear documentation and structure

## Getting Started

Basic usage (build commands and setup instructions) will be documented soon.
For now, refer to:

- [`doc/usage.md`](doc/usage.md) - How to build and run database images
- [`doc/patching.md`](doc/patching.md) - How to add patch ZIPs and metadata
- [`doc/build_matrix.md`](doc/build_matrix.md) - Overview of supported builds

## Patch and Metadata Layout

Patch ZIPs and metadata are stored by version and platform:

```text
database/19/software/amd64/RU_19.27.0.0/oracle_package_names_amd64
```

Each file defines the ZIPs required to build a specific image.
The build script `buildDB.sh` uses this metadata to assemble the final image.

## Contributing

- Fork and submit pull requests
- Open issues for bugs or enhancements
- Contributions from Oracle DBAs, developers, and the wider community are welcome

## License

- Code is licensed under the [Apache 2.0 License](LICENSE)
- Oracle binaries must be downloaded separately and used in accordance with Oracle's license terms

## Maintainer

**Stefan Oehrli**
[oradba.ch](https://www.oradba.ch) · [GitHub @oehrli](https://github.com/oehrli)
