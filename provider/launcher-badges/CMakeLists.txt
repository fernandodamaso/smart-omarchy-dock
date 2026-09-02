cmake_minimum_required(VERSION 3.20)
project(smartdock_launcher_badge_provider LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core DBus Test)

add_library(smartdock_launcher_badge_model STATIC
  LauncherBadgeModel.cpp
)
target_include_directories(smartdock_launcher_badge_model PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)
target_compile_options(smartdock_launcher_badge_model PRIVATE
  -Wall -Wextra -Wpedantic
)

add_executable(smartdock-launcher-badge-provider
  main.cpp
  LauncherBadgeProvider.cpp
  LauncherBadgeProvider.h
)
target_link_libraries(smartdock-launcher-badge-provider PRIVATE
  smartdock_launcher_badge_model
  Qt6::Core
  Qt6::DBus
)
target_compile_options(smartdock-launcher-badge-provider PRIVATE
  -Wall -Wextra -Wpedantic
)

include(CTest)
if(BUILD_TESTING)
  add_executable(test_launcher_badge_provider_model
    tests/test_provider_model.cpp
  )
  target_link_libraries(test_launcher_badge_provider_model PRIVATE
    smartdock_launcher_badge_model
  )
  add_test(NAME launcher_badge_provider_model
    COMMAND test_launcher_badge_provider_model)

  add_executable(test_launcher_badge_provider_fixtures
    tests/tst_provider_fixtures.cpp
  )
  target_link_libraries(test_launcher_badge_provider_fixtures PRIVATE
    smartdock_launcher_badge_model
    Qt6::Core
    Qt6::Test
  )
  target_compile_definitions(test_launcher_badge_provider_fixtures PRIVATE
    SMARTDOCK_LAUNCHER_BADGE_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
  )
  add_test(NAME launcher_badge_provider_fixtures
    COMMAND test_launcher_badge_provider_fixtures)
endif()

install(TARGETS smartdock-launcher-badge-provider
  RUNTIME DESTINATION .)
