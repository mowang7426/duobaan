#!/bin/sh
# Run from the repository root. Compile/link checks only, NOT an app build.
# Uses Apelin's prepared clang and SDKROOT; no downloads or execution.
set -eu
test -f Application/Dopamine/UI/DOWallpaperController.m
mkdir -p .build/wallpaper
find Application/Dopamine -type d > .build/wallpaper/include-directories.txt
set --
while IFS= read -r directory; do
    set -- "$@" "-I$directory"
done < .build/wallpaper/include-directories.txt
for arch in arm64 arm64e; do
    for name in DOWallpaperImage DOWallpaperController; do
        clang -arch "$arch" -miphoneos-version-min=15.0 -fobjc-arc -fmodules \
            -fmodules-cache-path=.build/wallpaper/modules \
            -Wall -Wextra -Werror -Wno-unused-parameter \
            -c "Application/Dopamine/UI/$name.m" -o ".build/wallpaper/$name-$arch.o"
    done
    # Existing upstream headers use deprecated UIKit declarations. Keep warnings visible.
    clang -arch "$arch" -miphoneos-version-min=15.0 -fobjc-arc -fmodules \
        -fmodules-cache-path=.build/wallpaper/modules -FApplication/Frameworks "$@" \
        -c Application/Dopamine/UI/DONavigationController.m \
        -o ".build/wallpaper/DONavigationController-$arch.o"
    clang -arch "$arch" -miphoneos-version-min=15.0 -fobjc-arc -fmodules \
        -fmodules-cache-path=.build/wallpaper/modules \
        -Wall -Wextra -Werror -Wno-unused-parameter \
        -IApplication/Dopamine/UI Tests/WallpaperImageTests.m \
        ".build/wallpaper/DOWallpaperImage-$arch.o" \
        -framework Foundation -framework CoreGraphics -framework ImageIO \
        -framework UniformTypeIdentifiers -o ".build/wallpaper/WallpaperImageTests-$arch"
done
printf '%s\n' 'PASS: wallpaper image/controller/navigation compile; image test binaries link (arm64 and arm64e).'
printf '%s\n' 'NOT CHECKED: main controller, full app build/link/assets, test execution, or UI behavior.'
