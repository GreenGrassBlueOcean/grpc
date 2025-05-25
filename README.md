<!-- badges: start -->
[![R-CMD-check](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/GreenGrassBlueOcean/grpc/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

# grpc: An R Interface to gRPC

This R library provides an interface to [gRPC](https://grpc.io/), a high-performance, open-source universal Remote Procedure Call (RPC) framework. It enables the creation of gRPC clients and servers within R, facilitating communication with distributed services.

This package is currently being updated to use modern gRPC C-core libraries for improved robustness and compatibility, with an initial focus on unary RPCs.

## Installation

### Dependencies

*   **R (>= 4.x recommended)**
*   **Rcpp (>= 0.12.5):** For C++ integration.
*   **RProtoBuf:** For Protocol Buffer message handling in R.
*   **A C++17 compatible compiler:** Such as the one provided by modern Rtools.
*   **gRPC C-core libraries and Protocol Buffer libraries:** These need to be available to your C++ compiler.

### Setup for Windows (using Rtools4x with UCRT and MSYS2)

This guide assumes you are using Rtools4x (which includes MSYS2 with a UCRT64 environment).

1.  **Install R and Rtools4x:**
    *   Ensure you have a recent version of R (4.0.0 or later, UCRT versions like 4.2.0+ are recommended).
    *   Download and install the corresponding Rtools4x from [CRAN](https://cran.r-project.org/bin/windows/Rtools/).
    *   **During the Rtools4x installation, ensure you check the box that says "Add Rtools to system PATH" (or similar wording).** This is critical for R to find the compilers and tools.

2.  **Verify Rtools on PATH:**
    *   After installation, open a **new** Command Prompt or PowerShell window (not one that was open before the Rtools installation finished).
    *   Type `gcc -v`. You should see output from the Rtools `gcc.exe` compiler.
    *   Type `pacman -Syu`. This should launch the MSYS2 package manager update process.
    *   **If these commands are not found:** You'll need to manually add the Rtools directories to your system PATH environment variable. Typically, these are:
        *   `C:\rtools4X\ucrt64\bin` (replace `rtools4X` with your Rtools version, e.g., `rtools45`)
        *   `C:\rtools4X\usr\bin`
        *   To do this:
            1.  Search for "environment variables" in the Windows Start Menu.
            2.  Click "Edit the system environment variables".
            3.  In the System Properties window, click the "Environment Variables..." button.
            4.  Under "System variables" (or "User variables" if you prefer), find the variable named `Path` (or `PATH`).
            5.  Select it and click "Edit...".
            6.  Click "New" and add the two paths listed above (adjusting for your Rtools installation directory).
            7.  Click "OK" on all open dialogs.
            8.  **You will need to open a new Command Prompt/PowerShell/RStudio session for these PATH changes to take effect.**

3.  **Install gRPC and Protobuf development libraries via MSYS2:**
    *   Open the Rtools MSYS2 UCRT64 shell (usually found via the Start Menu, e.g., "Rtools UCRT64").
    *   Update the package database and install necessary packages:
        ```shell
        pacman -Syu  # Update package database (might need to run twice if core MSYS2 updates)
        pacman -Su   # Update installed packages
        # Essential build tools (gcc and make should come with Rtools, pkgconf is useful)
        pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make mingw-w64-ucrt-x86_64-pkgconf 
        # gRPC and Protocol Buffers libraries
        pacman -S mingw-w64-ucrt-x86_64-grpc mingw-w64-ucrt-x86_64-protobuf
        ```
    *   These commands install the gRPC C-core, gRPC++, Protocol Buffers, and `pkg-config` utility configured for your UCRT64 environment. The `src/Makevars.win` file in this R package is set up to use these libraries.

### Setup for Debian/Ubuntu (for pre-installed system libraries)

If you have gRPC and Protobuf libraries installed system-wide (e.g., via `apt`):

1.  **Install Pre-requisites:**
    ```shell
    sudo apt-get update
    sudo apt-get install build-essential autoconf libtool pkg-config cmake
    sudo apt-get install libgrpc-dev libgrpc++-dev protobuf-compiler libprotobuf-dev
    # For Abseil, often bundled or a separate install might be needed if your gRPC version requires it
    # sudo apt-get install libabsl-dev 
    ```
    *Note: Exact package names (`libgrpc-dev`, `libabsl-dev`) might vary slightly across distributions and versions. Use `apt search` if needed.*

2.  **R Package Installation:**
    The R package's `configure` script (and `src/Makevars.in`) will attempt to use `pkg-config` to find these system libraries.

### Installing the R Package (from Source/GitHub)

1.  **Clone the repository (if you haven't already):**
    ```shell
    git clone https://github.com/GreenGrassBlueOcean/grpc.git # Replace with your repo URL
    cd grpc
    ```
2.  **Install in R:**
    Open R or RStudio in the package's root directory.
    ```R
    # For development:
    devtools::install() 
    # Or to build and install from a source tarball:
    # R CMD build .
    # R CMD INSTALL grpc_*.tar.gz
    ```

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

*(The original HelloWorld, Health Check, and Iris demos will be fully functional once the R handler dispatch is completed in the C++ server.)*

## Todo (Key Items)

*   **Complete R Handler Dispatch:** Fully implement the mechanism in `server.cpp` for `robust_grpc_server_run` to dynamically call R functions provided in the `impl` argument based on the RPC method.
*   **Streaming Services:** Add C++ support and R wrappers for client-side, server-side, and bidirectional streaming RPCs.
*   **Authentication and Encryption (TLS):** Implement support for secure channels.
*   **Error Handling:** More refined error propagation between C++ and R, and richer error details.
*   **Documentation:** Comprehensive Roxygen documentation, vignettes, and updated examples.
*   **`read_services` Parser:** Ensure `parser.R` (`read_services`) is robust and aligns with the `impl`/`services` structure expected by `start_server` and `grpc_client`.

## Contributing

Contributions are welcome! Please feel free to fork the repository, make changes, and submit pull requests. If you encounter issues or have feature requests, please open an issue on GitHub.

## Original Acknowledgement
This package builds upon the foundational work by Neal Fultz and Google in the original `nfultz/grpc` R package.
