cmake_minimum_required(VERSION 3.24)

include(FetchContent)
FetchContent_Declare(
    nvcodec
    GIT_REPOSITORY https://github.com/FFmpeg/nv-codec-headers.git
    GIT_TAG        n13.1.15.0
    GIT_SHALLOW    TRUE
)
FetchContent_GetProperties(nvcodec)
if(NOT nvcodec_POPULATED)
    FetchContent_Populate(nvcodec)
endif()

add_executable(vrmc_host
    src/main.cpp
    src/win_capture.cpp
    src/nvenc_encoder.cpp
    src/file_source.cpp
)
target_include_directories(vrmc_host PRIVATE
    ${CMAKE_SOURCE_DIR}/core/include
    ${nvcodec_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(vrmc_host PRIVATE vrmc_core ws2_32 d3d11 dxgi windowsapp mfplat mfuuid shlwapi)
target_compile_features(vrmc_host PRIVATE cxx_std_20)
target_compile_definitions(vrmc_host PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
set_target_properties(vrmc_host PROPERTIES
    OUTPUT_NAME vrmc_host
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/win64"
)
if(MSVC)
    target_compile_options(vrmc_host PRIVATE /W4 /permissive- /EHsc)
endif()
