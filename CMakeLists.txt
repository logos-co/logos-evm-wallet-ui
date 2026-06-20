cmake_minimum_required(VERSION 3.14)
project(WalletUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal UI module: we write the .rep view contract + the *Backend class;
# REP_FILE runs repc and the generated *Plugin glue (Q_PLUGIN_METADATA, initLogos
# wiring, QtRO registration) is compiled automatically.
logos_module(
    NAME wallet_ui
    REP_FILE src/wallet_ui.rep
    SOURCES
        src/wallet_ui_backend.h
        src/wallet_ui_backend.cpp
    INCLUDE_DIRS
        src
)
