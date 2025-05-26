AC_PREREQ([2.69])
AC_INIT([grpc], [0.2.1], [laurens@email.com])
AC_CONFIG_SRCDIR([src/client.cpp])
AC_CONFIG_HEADERS([src/config.h])
AC_CONFIG_AUX_DIR([tools]) # Make sure this directory exists or remove if not used

AC_PROG_CXX
AC_PROG_CC
# AC_PROG_CPP # Often not needed if CXX handles preprocessing
AC_PROG_LN_S
AC_PROG_MAKE_SET

# C++17 support
AX_CXX_COMPILE_STDCXX([17], [noext], [mandatory]) # This adds -std=c++17 (or similar) to CXX
AC_SUBST(CXX_STD, CXX17) # Based on AX_CXX_COMPILE_STDCXX success for C++17.
                         # Or, more robustly, AX_CXX_COMPILE_STDCXX itself modifies CXX.
                         # So, in Makevars.in, CXX_STD might not be strictly needed if R's CXX already has the std flag.
                         # However, explicitly setting CXX_STD=CXX17 via R's mechanism is fine.

PKG_PROG_PKG_CONFIG([0.28])

# Check for grpc++ and its dependencies (protobuf is usually pulled by grpc++)
PKG_CHECK_MODULES([GRPC_DEPS], [grpc++ protobuf], [
    AC_MSG_NOTICE([Found grpc++ and protobuf via pkg-config.])
    # Use the raw flags from pkg-config. Filtering is usually not needed and can be harmful.
    # The system's pkg-config files should provide compatible flags.
    GRPC_PKG_CXXFLAGS="$GRPC_DEPS_CFLAGS"
    GRPC_PKG_LIBS="$GRPC_DEPS_LIBS"
],[
    AC_MSG_FAILURE([
--------------------------------------------------------------------
grpc++ or protobuf library not found via pkg-config.
Please install development packages (e.g., libgrpc++-dev, libprotobuf-dev).
'pkg-config --cflags --libs grpc++ protobuf' failed.
--------------------------------------------------------------------])
])

AC_SUBST([GRPC_PKG_CXXFLAGS])
AC_SUBST([GRPC_PKG_LIBS])

AC_CONFIG_FILES([src/Makevars:src/Makevars.in])
AC_OUTPUT
