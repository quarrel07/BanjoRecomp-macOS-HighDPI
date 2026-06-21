# Define the path to the entitlements file
set(ENTITLEMENTS_FILE ${CMAKE_SOURCE_DIR}/.github/macos/entitlements.plist)

# Set bundle properties
set_target_properties(BanjoRecompiled PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "BanjoRecompiled"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.github.Banjorecompiled"
        MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
        MACOSX_BUNDLE_ICON_FILE "appicon"
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_BINARY_DIR}/Info.plist
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS ${ENTITLEMENTS_FILE}
)

# Compile the app icon from the Icon Composer package (icons/appicon.icon).
#
# actool produces:
#   - Assets.car      : the compiled asset catalog, including the Liquid Glass icon used on
#                       macOS 26 (Tahoe) and later.
#   - appicon.icns    : a flattened fallback rendered by actool, used by macOS versions that
#                       predate the Liquid Glass icon system.
#   - a partial Info.plist (its keys, CFBundleIconName/CFBundleIconFile, are already set directly
#                       in Info.plist.in, so the generated partial plist is not consumed here).
# Both Assets.car and appicon.icns are copied into the bundle's Resources directory.
set(ICON_SOURCE ${CMAKE_SOURCE_DIR}/icons/appicon.icon)
set(ICON_COMPILE_DIR ${CMAKE_BINARY_DIR}/AppIconAssets)
set(ASSETS_CAR ${ICON_COMPILE_DIR}/Assets.car)
set(ICNS_FALLBACK ${ICON_COMPILE_DIR}/appicon.icns)
set(ICON_PARTIAL_PLIST ${ICON_COMPILE_DIR}/icon-partial-info.plist)

add_custom_command(
        OUTPUT ${ASSETS_CAR} ${ICNS_FALLBACK}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${ICON_COMPILE_DIR}
        COMMAND xcrun actool ${ICON_SOURCE}
                --compile ${ICON_COMPILE_DIR}
                --app-icon appicon
                --output-partial-info-plist ${ICON_PARTIAL_PLIST}
                --platform macosx
                --target-device mac
                --minimum-deployment-target ${CMAKE_OSX_DEPLOYMENT_TARGET}
                --errors --warnings
        DEPENDS ${ICON_SOURCE}/icon.json
        COMMENT "Compiling app icon (Icon Composer) with actool"
)

# Custom target to ensure the icon is compiled before the bundle is assembled.
add_custom_target(create_icns ALL DEPENDS ${ASSETS_CAR} ${ICNS_FALLBACK})

# Copy the compiled catalog and fallback icns into the bundle's Resources directory.
set_source_files_properties(${ASSETS_CAR} ${ICNS_FALLBACK} PROPERTIES
        GENERATED TRUE
        MACOSX_PACKAGE_LOCATION "Resources"
)
target_sources(BanjoRecompiled PRIVATE ${ASSETS_CAR} ${ICNS_FALLBACK})

# Ensure BanjoRecompiled depends on the icon compilation.
add_dependencies(BanjoRecompiled create_icns)

# Configure Info.plist
configure_file(${CMAKE_SOURCE_DIR}/.github/macos/Info.plist.in ${CMAKE_BINARY_DIR}/Info.plist @ONLY)

# Install the app bundle
install(TARGETS BanjoRecompiled BUNDLE DESTINATION .)

# Ensure the entitlements file exists
if(NOT EXISTS ${ENTITLEMENTS_FILE})
    message(FATAL_ERROR "Entitlements file not found at ${ENTITLEMENTS_FILE}")
endif()

# Post-build steps for macOS bundle
add_custom_command(TARGET BanjoRecompiled POST_BUILD
    # Copy and fix frameworks first
    COMMAND ${CMAKE_COMMAND} -D CMAKE_BUILD_TYPE=$<CONFIG> -D CMAKE_GENERATOR=${CMAKE_GENERATOR} -P ${CMAKE_SOURCE_DIR}/.github/macos/fixup_bundle.cmake

    # Copy all resources
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/assets ${CMAKE_BINARY_DIR}/temp_assets
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/temp_assets/scss
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/temp_assets $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Resources/assets
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/temp_assets

    # Copy controller database
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/recompcontrollerdb.txt $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Resources/

    # Set RPATH
    COMMAND install_name_tool -add_rpath "@executable_path/../Frameworks/" $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/MacOS/BanjoRecompiled

    # Sign the bundle
    COMMAND codesign --verbose=4 --options=runtime --no-strict --sign - --entitlements ${ENTITLEMENTS_FILE} --deep --force $<TARGET_BUNDLE_DIR:BanjoRecompiled>

    COMMENT "Performing post-build steps for macOS bundle"
    VERBATIM
)
