cmake_minimum_required(VERSION 3.24)
project(VRMCBridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(vrmc_core STATIC
    core/src/protocol.cpp
    core/src/ipc.cpp
)
target_include_directories(vrmc_core PUBLIC core/include)
target_compile_features(vrmc_core PUBLIC cxx_std_20)
if(MSVC)
    target_compile_options(vrmc_core PRIVATE /W4 /WX /permissive-)
else()
    target_compile_options(vrmc_core PRIVATE -Wall -Wextra -Werror)
endif()

add_executable(vrmc_core_tests tests/core_tests.cpp)
target_link_libraries(vrmc_core_tests PRIVATE vrmc_core)
target_compile_features(vrmc_core_tests PRIVATE cxx_std_20)
target_compile_definitions(vrmc_core_tests PRIVATE VRMC_VECTOR_DIR="${CMAKE_SOURCE_DIR}/../protocol/vectors")
if(MSVC)
    target_compile_options(vrmc_core_tests PRIVATE /W4 /permissive-)
else()
    target_compile_options(vrmc_core_tests PRIVATE -Wall -Wextra)
endif()
enable_testing()
add_test(NAME core COMMAND vrmc_core_tests)

if(WIN32)
    add_subdirectory(driver)
    add_subdirectory(host)
endif()
