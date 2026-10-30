cmake_minimum_required(VERSION 3.24)

include(FetchContent)
FetchContent_Declare(
    openvr
    GIT_REPOSITORY https://github.com/ValveSoftware/openvr.git
    GIT_TAG        v2.15.6
    GIT_SHALLOW    TRUE
)
FetchContent_GetProperties(openvr)
if(NOT openvr_POPULATED)
    FetchContent_Populate(openvr)
endif()

add_library(driver_vrmc SHARED
    src/driver.cpp
)
target_include_directories(driver_vrmc PRIVATE
    ${openvr_SOURCE_DIR}/headers
    ${CMAKE_SOURCE_DIR}/core/include
)
target_link_libraries(driver_vrmc PRIVATE vrmc_core)
target_compile_definitions(driver_vrmc PRIVATE VRMC_DRIVER_EXPORTS)
set_target_properties(driver_vrmc PROPERTIES
    OUTPUT_NAME driver_vrmc
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/win64"
)
if(MSVC)
    target_compile_options(driver_vrmc PRIVATE /W4 /permissive-)
endif()

# Copy the driver source tree into the build output for the installer.
add_custom_command(TARGET driver_vrmc POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
        "${CMAKE_BINARY_DIR}/bin/win64/resources"
)
