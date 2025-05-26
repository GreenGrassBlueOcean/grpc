<!-- badges: start -->

[![R-CMD-check](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml)

<!-- badges: end -->

# grpc: An R Interface to gRPC

This R library provides an interface to [gRPC](https://grpc.io/), a
high-performance, open-source universal Remote Procedure Call (RPC)
framework. It enables the creation of gRPC clients and servers within R,
facilitating communication with distributed services.

This package utilizes the gRPC C-core libraries for its underlying
implementation, aiming for robustness and compatibility. The current
focus is on unary RPCs, with plans for streaming support.

## Installation

### Prerequisites

-   **R (\>= 4.x recommended)**
-   **Rcpp (\>= 0.12.5):** For C++ integration.
-   **RProtoBuf:** For Protocol Buffer message handling in R. (You may
    need to install its system dependencies first, e.g.,
    `libprotobuf-dev` and `protobuf-compiler` on Linux, or `protobuf`
    via Homebrew on macOS).
-   **A C++17 compatible compiler:** Such as the one provided by modern
    Rtools (Windows), or standard compilers on Linux/macOS.
-   **gRPC C-core libraries (development headers and compiled
    libraries):** These are essential for compiling the R package.
-   **Protocol Buffer libraries (development headers and compiled
    libraries):** Required by gRPC.
-   **Standard Build Tools:** `make`, `pkg-config`, `autoconf`,
    `automake`, `libtool`, `cmake`.

### Platform-Specific Setup Instructions

**Windows (using Rtools4x with UCRT and MSYS2)**

This guide assumes you are using Rtools4x (e.g., Rtools43, Rtools44)
which includes MSYS2 with a UCRT64 environment.

1.  **Install R and Rtools4x:**
    -   Ensure you have a recent version of R (4.2.0+ UCRT versions are
        recommended).
    -   Download and install the corresponding Rtools4x from
        [CRAN](https://cran.r-project.org/bin/windows/Rtools/).
    -   During Rtools4x installation, ensure "Add Rtools to system PATH"
        is checked.
2.  **Verify Rtools on PATH:**
    -   Open a **new** Command Prompt or PowerShell.
    -   Type `gcc -v` and `make -v`. You should see output from the
        Rtools `gcc.exe` and `make.exe`.
    -   If not found, manually add Rtools directories (e.g.,
        `C:\rtools4X\ucrt64\bin`, `C:\rtools4X\usr\bin`) to your system
        PATH. Remember to open a new terminal/RStudio session after
        changing the PATH.
3.  **Install gRPC, Protobuf, and Build Tools via MSYS2 UCRT64 Shell:**
    -   Open the Rtools MSYS2 UCRT64 shell (e.g., from the Start Menu).

    -   Update package databases and install dependencies:

        ``` shell
        pacman -Syu  # Update all (may need to run twice if core MSYS2 updates)

        # Essential build tools for this package and its dependencies
        pacman -S --needed --noconfirm \
            mingw-w64-ucrt-x86_64-make \
            mingw-w64-ucrt-x86_64-gcc \
            mingw-w64-ucrt-x86_64-pkgconf \
            # Autotools are needed if you plan to regenerate ./configure from configure.ac
            # mingw-w64-ucrt-x86_64-autotools # This is a group, or install individually:
            # mingw-w64-ucrt-x86_64-autoconf mingw-w64-ucrt-x86_64-automake mingw-w64-ucrt-x86_64-libtool
            # (Note: For running autoreconf, sometimes using the msys/* versions from the MSYS2 shell is more straightforward)

        # gRPC and Protocol Buffers libraries (ensure these are recent, e.g., gRPC >= 1.48.x)
        pacman -S --needed --noconfirm \
            mingw-w64-ucrt-x86_64-grpc \
            mingw-w64-ucrt-x86_64-protobuf
        ```

    -   The `src/Makevars.win` file in this R package is configured to
        use these libraries.

**macOS (using Homebrew)**

1.  **Install Homebrew** if you haven't already (see
    [brew.sh](https://brew.sh/)).
2.  **Install Prerequisites via Homebrew:**
    `shell     brew update     brew install pkg-config autoconf automake autoconf-archive libtool cmake     brew install grpc protobuf     # Ensure Rcpp and RProtoBuf are installed in R (see R package installation below)`
3.  The R package's `configure` script will use `pkg-config` to find
    these libraries.

**Linux (Debian/Ubuntu)**

System-provided gRPC packages (like `libgrpc-dev`) on some Linux
distributions (especially older ones or certain Ubuntu versions like
24.04 with `libgrpc-dev 1.51.1`) may be incomplete or have an
incompatible header layout for direct C-core usage as required by this
package (e.g., missing `grpc/credentials.h`).

**Recommended Method for Linux: Build gRPC from Source** This is the
most reliable way to ensure a compatible and complete gRPC installation.
The GitHub Actions workflow for this package uses this method for Linux
builds.

1.  **Install Build Tools and Protobuf:**
    `shell     sudo apt-get update     sudo apt-get install -y --no-install-recommends \         build-essential autoconf libtool pkg-config cmake git clang \         protobuf-compiler libprotobuf-dev`
2.  **Build and Install gRPC (example for a specific version, adjust as
    needed):**
    `shell     GRPC_VERSION="v1.54.2" # A known stable version; v1.72.0 also used on macOS/Windows                            # Or use a more recent stable release.     cd /tmp # Or any temporary build directory     git clone --depth 1 --branch ${GRPC_VERSION} https://github.com/grpc/grpc     cd grpc     git submodule update --init # Crucial for dependencies     mkdir -p cmake/build     cd cmake/build     cmake ../.. \         -DCMAKE_BUILD_TYPE=Release \         -DCMAKE_INSTALL_PREFIX=/usr/local \         -DBUILD_SHARED_LIBS=ON \         -DgRPC_INSTALL=ON \         -DgRPC_BUILD_TESTS=OFF \         -DgRPC_ABSL_PROVIDER=module \         -DgRPC_CARES_PROVIDER=module \         -DgRPC_PROTOBUF_PROVIDER=module \         -DgRPC_RE2_PROVIDER=module \         -DgRPC_SSL_PROVIDER=module \         -DgRPC_ZLIB_PROVIDER=module     make -j$(nproc)     sudo make install     sudo ldconfig`
    This installs gRPC to `/usr/local`. The R package's `configure`
    script will find it if `/usr/local/lib/pkgconfig` is in
    `PKG_CONFIG_PATH` (often default or can be set).

**Alternative for Linux (Using System Packages - Use with Caution):** If
you choose to use system-provided gRPC: \`\`\`shell sudo apt-get install
libgrpc-dev libgrpc++-dev \# (and previously mentioned build tools)
