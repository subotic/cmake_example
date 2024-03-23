include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(sipi_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(sipi_setup_options)
  option(sipi_ENABLE_HARDENING "Enable hardening" ON)
  option(sipi_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    sipi_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    sipi_ENABLE_HARDENING
    OFF)

  sipi_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR sipi_PACKAGING_MAINTAINER_MODE)
    option(sipi_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(sipi_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(sipi_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sipi_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sipi_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sipi_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(sipi_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(sipi_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sipi_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(sipi_ENABLE_IPO "Enable IPO/LTO" ON)
    option(sipi_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(sipi_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sipi_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(sipi_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(sipi_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sipi_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sipi_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sipi_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(sipi_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(sipi_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sipi_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      sipi_ENABLE_IPO
      sipi_WARNINGS_AS_ERRORS
      sipi_ENABLE_USER_LINKER
      sipi_ENABLE_SANITIZER_ADDRESS
      sipi_ENABLE_SANITIZER_LEAK
      sipi_ENABLE_SANITIZER_UNDEFINED
      sipi_ENABLE_SANITIZER_THREAD
      sipi_ENABLE_SANITIZER_MEMORY
      sipi_ENABLE_UNITY_BUILD
      sipi_ENABLE_CLANG_TIDY
      sipi_ENABLE_CPPCHECK
      sipi_ENABLE_COVERAGE
      sipi_ENABLE_PCH
      sipi_ENABLE_CACHE)
  endif()

  sipi_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (sipi_ENABLE_SANITIZER_ADDRESS OR sipi_ENABLE_SANITIZER_THREAD OR sipi_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(sipi_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(sipi_global_options)
  if(sipi_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    sipi_enable_ipo()
  endif()

  sipi_supports_sanitizers()

  if(sipi_ENABLE_HARDENING AND sipi_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sipi_ENABLE_SANITIZER_UNDEFINED
       OR sipi_ENABLE_SANITIZER_ADDRESS
       OR sipi_ENABLE_SANITIZER_THREAD
       OR sipi_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${sipi_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${sipi_ENABLE_SANITIZER_UNDEFINED}")
    sipi_enable_hardening(sipi_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(sipi_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(sipi_warnings INTERFACE)
  add_library(sipi_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  sipi_set_project_warnings(
    sipi_warnings
    ${sipi_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(sipi_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    sipi_configure_linker(sipi_options)
  endif()

  include(cmake/Sanitizers.cmake)
  sipi_enable_sanitizers(
    sipi_options
    ${sipi_ENABLE_SANITIZER_ADDRESS}
    ${sipi_ENABLE_SANITIZER_LEAK}
    ${sipi_ENABLE_SANITIZER_UNDEFINED}
    ${sipi_ENABLE_SANITIZER_THREAD}
    ${sipi_ENABLE_SANITIZER_MEMORY})

  set_target_properties(sipi_options PROPERTIES UNITY_BUILD ${sipi_ENABLE_UNITY_BUILD})

  if(sipi_ENABLE_PCH)
    target_precompile_headers(
      sipi_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(sipi_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    sipi_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(sipi_ENABLE_CLANG_TIDY)
    sipi_enable_clang_tidy(sipi_options ${sipi_WARNINGS_AS_ERRORS})
  endif()

  if(sipi_ENABLE_CPPCHECK)
    sipi_enable_cppcheck(${sipi_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(sipi_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    sipi_enable_coverage(sipi_options)
  endif()

  if(sipi_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(sipi_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(sipi_ENABLE_HARDENING AND NOT sipi_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sipi_ENABLE_SANITIZER_UNDEFINED
       OR sipi_ENABLE_SANITIZER_ADDRESS
       OR sipi_ENABLE_SANITIZER_THREAD
       OR sipi_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    sipi_enable_hardening(sipi_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
