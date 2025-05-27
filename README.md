<!-- badges: start -->

[![R-CMD-check](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml)

<!-- badges: end -->

# grpc: An R Interface to gRPC

This R package provides an interface to [gRPC](https://grpc.io/), a modern, high-performance, open-source universal Remote Procedure Call (RPC) framework. It enables R users to develop gRPC clients and servers, allowing R applications to communicate efficiently with services written in various languages.

This package is built upon the gRPC C-core libraries for direct and robust interaction. The current development primarily supports unary RPCs, with ongoing work to expand capabilities including streaming services.

## Features (Current & Planned)

-   **Unary RPCs:** Client and server support for request-response interactions.
-   **C-core Base:** Direct use of gRPC's underlying C libraries.
-   **R Handler Integration:** (In progress) Mechanism for R functions to handle server-side RPC logic.
-   **Cross-Platform:** Aims for compatibility with Windows, macOS, and Linux.
-   *(Planned) Streaming RPCs (Client-side, Server-side, Bidirectional)*
-   *(Planned) Authentication & TLS Support*
-   *(Planned) Enhanced Error Handling and Metadata Support*

## System Dependencies

Successful compilation and use of this R package require several system-level dependencies to be installed and configured correctly.

**Core Requirements:**

1.  **R:** Version 4.0.0 or later is recommended. UCRT versions of R (e.g., R 4.2.0+) are preferred on Windows.
2.  **C++17 Compiler:** A modern C++ compiler supporting the C++17 standard (e.g., from Rtools4x on Windows, or standard GCC/Clang on Linux/macOS).
3.  **gRPC C-core Libraries:** Development headers and compiled libraries for gRPC. Version consistency across platforms is ideal (e.g., targeting gRPC `v1.72.0` or a recent stable release).
4.  **Protocol Buffers Libraries:** Development headers, compiled libraries, and the `protoc` compiler. gRPC relies heavily on Protocol Buffers.
5.  **Standard Build Tools:**
    -   `make`
    -   `pkg-config` (or `pkgconf`)
    -   `cmake` (especially if building gRPC from source)
    -   `autoconf`, `automake`, `libtool` (if you intend to modify `configure.ac` and regenerate the `./configure` script)
6.  **R Packages:**
    -   `Rcpp` (\>= 0.12.5): For C++ integration within R.
    -   `RProtoBuf`: For handling Protocol Buffer messages in R.
    -   `devtools` (optional, for development): For `devtools::install()`.
    -   `futile.logger` (optional, for development): Used for verbose logging in example/test code.

### Platform-Specific Setup Instructions

**Important:** Before attempting to install the R package, ensure the system dependencies listed above are met for your operating system.

------------------------------------------------------------------------

#### **Windows (using Rtools4x with UCRT and MSYS2)**

This guide assumes you are using a recent Rtools4x version (e.g., Rtools42, Rtools43, Rtools44) which provides an MSYS2 UCRT64 environment.

1.  **Install R and Rtools4x:**
    -   Install a UCRT version of R (e.g., R 4.2.0 or newer).
    -   Download and install the corresponding Rtools4x from [CRAN](https://cran.r-project.org/bin/windows/Rtools/).
    -   **Crucial:** During Rtools4x installation, ensure the option "Add Rtools to system PATH" is checked.
2.  **Verify Rtools PATH Configuration:**
    -   After installation, open a **new** Command Prompt or PowerShell window (not one that was open during the Rtools installation).
    -   Type `gcc -v` and then `make -v`. You should see version information from the Rtools compilers.
    -   If these commands are not found, you must manually add the Rtools directories to your system PATH. These typically include:
        -   `C:\rtools4X\ucrt64\bin` (e.g., `C:\rtools44\ucrt64\bin`)
        -   `C:\rtools4X\usr\bin`
    -   Restart any open terminals or RStudio sessions after modifying the PATH for changes to take effect.
3.  **Install gRPC, Protobuf, and Build Tools via MSYS2 UCRT64 Shell:**
    -   Open the "Rtools UCRT64" shell from your Windows Start Menu.

    -   Update MSYS2 and install the required MinGW packages:

        ``` bash
        # Update MSYS2 system and package databases (may require closing and reopening the shell)
        pacman -Syu 
        pacman -Su

        # Install essential MinGW-w64 UCRT64 build tools
        pacman -S --needed --noconfirm \
            mingw-w64-ucrt-x86_64-make \
            mingw-w64-ucrt-x86_64-gcc \
            mingw-w64-ucrt-x86_64-pkgconf

        # Install gRPC and Protocol Buffers development libraries for UCRT64
        # Target gRPC v1.72.0 or a similarly recent version if available
        pacman -S --needed --noconfirm \
            mingw-w64-ucrt-x86_64-grpc \
            mingw-w64-ucrt-x86_64-protobuf

        # For developers modifying configure.ac: install autotools (msys versions)
        # pacman -S --needed --noconfirm msys/autoconf msys/automake msys/libtool msys/autoconf-archive
        ```

    -   This R package's `src/Makevars.win` is designed to locate these UCRT64 libraries using `pkg-config`.

------------------------------------------------------------------------

#### **macOS (using Homebrew)**

1.  **Install Homebrew:** If not already installed, follow instructions at [brew.sh](https://brew.sh/).
2.  **Install Prerequisites via Homebrew:** Open your Terminal and run: `bash     brew update     brew install pkg-config autoconf automake autoconf-archive libtool cmake     brew install grpc protobuf      # This typically installs recent versions, e.g., gRPC v1.72.0.`
3.  The R package's `configure` script will use `pkg-config` (provided by Homebrew) to find the installed libraries.

------------------------------------------------------------------------
## Linux (Debian/Ubuntu)

System packages such as **libgrpc-dev** are often outdated, incomplete, or mis-configured.  
The most reliable approach is to **build gRPC from source**, exactly as done in this package’s GitHub Actions CI.

---

### 1  Install core build tools and system **libprotobuf-dev**

```bash
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    build-essential autoconf libtool pkg-config cmake git clang \
    protobuf-compiler libprotobuf-dev
```
`libprotobuf-dev` is required by RProtoBuf, a dependency of this R packag


### 2 Clone, build, and install gRPC
```bash
GRPC_VERSION="v1.72.0"   # Adjust if you need a different tag
cd /tmp                  # Temporary build directory

git clone --depth 1 --branch "${GRPC_VERSION}" https://github.com/grpc/grpc
cd grpc
git submodule update --init --recursive       # Pull Abseil, c-ares, etc.

mkdir -p cmake/build && cd cmake/build

cmake ../.. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DBUILD_SHARED_LIBS=ON \
  -DgRPC_INSTALL=ON \
  -DgRPC_BUILD_TESTS=OFF \
  -DgRPC_ABSL_PROVIDER=module \
  -DgRPC_CARES_PROVIDER=module \
  -DgRPC_SSL_PROVIDER=module \
  -DgRPC_ZLIB_PROVIDER=module \
  -DgRPC_PROTOBUF_PROVIDER=module   # Use gRPC’s vendored Protobuf

make -j"$(nproc)"
sudo make install
sudo ldconfig                                # Refresh linker cache
```
### 3 Remove gRPC’s vendored protobuf.pc
gRPC installs its own `protobuf.pc` in `/usr/local/lib{,64}/pkgconfig/`.
That file can override the system one needed by RProtoBuf.

```bash
sudo rm -f /usr/local/lib/pkgconfig/protobuf.pc \
           /usr/local/lib64/pkgconfig/protobuf.pc
```
### 4 (Optional) Set PKG_CONFIG_PATH
Ensure the system paths come first so pkg-config finds the correct files:

```bash
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig"
```

## Alternative: distribution packages (**NOT recommended**)

You *can* install **`libgrpc-dev`** via APT, but be prepared for several issues:

- **Missing headers** (e.g., `grpc/credentials.h`)
- **Broken or conflicting** `.pc` files
- **Version mismatches** with **RProtoBuf**

> **Use this approach only with extreme caution.**

---

## Why build from source?

- Guarantees a **complete, compatible** gRPC installation  
- Mirrors the setup **proven in CI**  
- Avoids errors such as **“Argument list too long”** caused by conflicting `protobuf.pc` files


### Installing the `grpc` R Package from GitHub

Once all **System Prerequisites** (compiler, gRPC libraries, Protocol Buffer libraries, build tools) for your specific operating system have been successfully installed and configured as detailed above, you can install the `grpc` R package directly from GitHub.

1.  **Ensure `remotes` (or `devtools`) R package is installed:** If you don't have it, install it from CRAN:
    ```R
    install.packages("remotes")      # or install.packages("devtools")
    ```

3.  **Install `grpc` from GitHub:** In your R console, run:
    ```R
    remotes::install_github("GreenGrassBlueOcean/grpc")
    # Or, if you prefer using devtools:
    # devtools::install_github("GreenGrassBlueOcean/grpc")`
    ```
   This command will download the package source, run the `configure` script (on Linux/macOS), compile the C++ code, and install the package into your R library.

**(For Developers Only) Building and Installing from a Local Clone:**

If you have cloned the repository locally and are making changes (especially to `configure.ac` or C++ code):

1.  **Clone the repository (if not already done):** `bash     git clone https://github.com/GreenGrassBlueOcean/grpc.git # Or your fork's URL     cd grpc`

2.  **(If `configure.ac` was modified) Regenerate Build Scripts:** Follow the `autoreconf -fi` instructions for your OS in the "Platform-Specific Setup Instructions" section to regenerate `./configure` and `aclocal.m4`.

3.  **Set up Git Line Endings:** Ensure `.gitattributes` is present and configured as described earlier to manage line endings correctly, especially for `configure` and `configure.ac`.

4.  **Install locally using `devtools` (recommended for development):** In an R session with the working directory set to the package root:

    ``` r
    # Ensure R dependencies are installed
    # install.packages(c("Rcpp", "RProtoBuf", "devtools", "futile.logger")) 

    devtools::install(dependencies = TRUE)
    ```

5.  **Traditional `R CMD` build and install (alternative):** From your system terminal, in the package root directory: `bash     R CMD build .     R CMD INSTALL grpc_*.tar.gz      # (Replace * with the actual version from the tarball name)`

(Example: "The demo/ folder contains scripts for testing basic client/server functionality. Please ensure that if you are connecting to an external gRPC service, both the service and this R client are using compatible gRPC library versions and .proto definitions.")

Troubleshooting Common Issues

grpc/credentials.h: No such file or directory (or similar header not found errors) during R package installation: 
- This almost always indicates that the gRPC C-core development headers are not installed correctly or are not findable by your C++ compiler. 
- On Linux: This is common if using system libgrpc-dev that is incomplete. Building gRPC from source (see Linux instructions) is the most reliable fix. 
- On macOS: Ensure brew install grpc completed successfully and pkg-config is in your PATH. Check pkg-config --cflags grpc. 
- On Windows: Ensure mingw-w64-ucrt-x86_64-grpc was installed via pacman in the Rtools UCRT64 shell, and that your src/Makevars.win is correctly using pkg-config. 
Linker errors (undefined reference to grpc\_...): - The gRPC compiled libraries were not found or linked correctly. 
- Ensure pkg-config --libs grpc (and grpc++) returns correct linker flags and that your Makevars / Makevars.win passes these to the linker. 
- On Linux, if building gRPC from source, ensure sudo ldconfig was run after sudo make install. configure script permission warnings - on Windows during R CMD check: Ensure the ./configure script is committed to Git with execute permissions and LF line endings. Use .gitattributes and git update-index --chmod=+x configure as described in the "Installing the R Package" section.

## Current Status & Examples

The package is currently undergoing significant updates to its C++ core for robustness with modern gRPC libraries.
*   Core unary RPC client (`robust_grpc_client_call`) and server (`robust_grpc_server_run`) functionalities in C++ have been established and tested.
*   The C++ server can call R functions for lifecycle hooks.
*   Work is in progress to fully integrate dynamic dispatch from the C++ server to R functions for handling RPC service logic (as defined by the `impl` argument in `start_server`).

### Testing the Core C++ Client/Server

The `demo/` folder contains scripts for testing:
*   `server-test1.r`: Starts the gRPC server. The C++ server currently calls R hooks and (if R handler dispatch is implemented) will call R functions from the `impl` argument. For now, it might send a fixed C++ reply if R dispatch is not yet complete.
*   `client-test2.r`: Acts as a client to the server started by `server-test1.r`.

**To run the basic test (demonstrating C++ core functionality and R hooks):**

1.  **Start the Server (Session 1):**
    Open an R session, navigate to the package source directory.
    ```R
    # devtools::load_all(".") # If developing interactively
    # library(grpc) # If installed
    source("demo/server-test1.r") # Adjust path if needed
    ```
    Observe the console for the port number the server starts on (e.g., `listening on port XXXXX`).

2.  **Run the Client (Session 2):**
    Open another R session, navigate to the package source directory.
    ```R
    # devtools::load_all(".") # If developing interactively
    # library(grpc) # If installed
    ```
    Edit `demo/client-test2.r` to set `MANUALLY_ENTERED_PORT` to the port number from Session 1.
    ```R
    source("demo/client-test2.r") # Adjust path if needed
    ```
    This will test the end-to-end communication. With the current C++ server (before full R handler dispatch), the client will receive a fixed reply from C++. Once R handler dispatch is complete in C++, the client will receive the response generated by the R `dummy_r_handler_function` defined in `server-test1.r`.

## Current Status & Examples

The package provides core C-core based gRPC functionality for unary RPCs.

*   **Client:** A robust C-core client (`robust_grpc_client_call`) is implemented, capable of sending unary requests and receiving responses, including handling metadata.
*   **Server:** A robust C-core server (`robust_grpc_server_run`) is implemented.
    *   It can accept incoming unary RPC calls.
    *   It **dispatches incoming requests to R handler functions** provided by the user. The R functions receive the request payload (as a raw vector) and are expected to return a raw vector as the response.
    *   It supports R-level lifecycle hooks for events like server creation, binding, start, shutdown, and stop.
*   **Basic Demos:** The `demo/` folder contains scripts to test this client-server interaction:
    *   `demo/server-test1.r`: Starts a gRPC server that uses a simple R function (`dummy_r_handler_function`) to process requests. It also demonstrates the use of server lifecycle hooks.
    *   `demo/client-test2.r`: Acts as a client to the server started by `server-test1.r`, sending a request and printing the response received from the R handler via the C++ server.

**To run the primary demo (demonstrating C++ core functionality, R handler dispatch, and R hooks):**

1.  **Install the Package:** Ensure the `grpc` R package is installed with its dependencies (see "Installing the `grpc` R Package" above).

2.  **Start the Server (R Session 1):**
    Open an R session and navigate to the package's source directory (if running from source) or ensure the package is loaded from your library.
    ```R
    # If developing interactively from source:
    # devtools::load_all(".") 
    # library(grpc) # Or load if already installed

    # Source the demo server script
    source("demo/server-test1.r") # Adjust path if needed, or call functions directly if loaded
    ```
    The console will output "Robust Server: Started, listening on port XXXXX". Note this port number.

3.  **Run the Client (R Session 2):**
    Open another R session.
    ```R
    # If developing interactively from source:
    # devtools::load_all(".")
    # library(grpc) # Or load if already installed
    ```
    Edit the `demo/client-test2.r` script:
    *   Set `MANUALLY_ENTERED_PORT` to the port number reported by the server in Session 1.
    *   You can also adjust `method_to_call` and `request_payload_str`. The `dummy_r_handler_function` in `server-test1.r` is set up to handle the method `/example.ExampleService/SayHello`.
    Then run the client script:
    ```R
    source("demo/client-test2.r") # Adjust path if needed
    ```
    The client will send a request. The C++ server will receive it, convert the payload, call the `dummy_r_handler_function` in R, receive its response, convert it back, and send it to the client. The client will then print the received response.

*(The original HelloWorld, Health Check, and Iris demos from `nfultz/grpc` would need to be adapted to use this new C-core client/server implementation and the R handler dispatch mechanism for full functionality.)*

## Todo (Key Items)

*   **Streaming Services:** Design and implement C++ support and R wrappers for client-side, server-side, and bidirectional streaming RPCs using the C-core API. This is a major next step.
*   **Authentication and Encryption (TLS):** Implement support for secure channels (e.g., using `grpc_ssl_credentials_create` for clients and `grpc_ssl_server_credentials_create` for servers).
*   **Error Handling & Status Details:**
    *   More refined error propagation from C++ to R exceptions, providing richer gRPC status codes and details to the R user.
    *   Allow R server handlers to return detailed status codes and error messages back to the client.
*   **Metadata Handling:**
    *   Expose server-side API for R handlers to read incoming request metadata.
    *   Expose server-side API for R handlers to set initial and trailing metadata for responses.
*   **`read_services` / `.proto` Integration:**
    *   Review and potentially enhance `parser.R` (`read_services`) to better integrate with the current server's expectation of a named list of R handler functions for the `impl` argument.
    *   Consider tools or workflows for users to easily go from `.proto` definitions to the required R handler function signatures and (de)serialization logic (perhaps by integrating more deeply with `RProtoBuf`'s capabilities for message types).
*   **Asynchronous Operations:** Explore exposing asynchronous client/server patterns to R if feasible and beneficial for advanced use cases.
*   **Documentation:**
    *   Comprehensive Roxygen documentation for all exported R functions and C++ functions exposed to R.
    *   Vignettes demonstrating common use cases (unary client, unary server, error handling, metadata).
    *   Update all examples in `demo/` to align with the current C-core implementation.
*   **Testing:** Robust unit and integration tests for client, server, and various RPC scenarios.
*   **Performance Profiling and Optimization:** Once core features are stable.


## Contributing

Contributions are welcome! Please feel free to fork the repository, make changes, and submit pull requests. If you encounter issues or have feature requests, please open an issue on GitHub.

## Original Acknowledgement
This package builds upon the foundational work by Neal Fultz and Google in the original `nfultz/grpc` R package.
