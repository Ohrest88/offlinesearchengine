#!/bin/bash

# Exit on error
set -e

echo "Building Flutter release..."
flutter build linux --release

echo "Creating AppImage structure..."
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/share/applications
mkdir -p AppDir/usr/share/icons/hicolor/256x256/apps

# Copy the bundle
echo "Copying application files..."
cp -r build/linux/x64/release/bundle/* AppDir/usr/bin/

# Create desktop entry
echo "Creating .desktop file..."
cat > AppDir/pocketsearchengine.desktop << EOF
[Desktop Entry]
Name=Pocket Search Engine
Exec=offline_engine
Icon=pocketsearchengine
Type=Application
Categories=Utility;
Comment=Offline semantic search engine for PDFs
EOF

# Copy icon
echo "Copying icon..."
cp assets/icon/icon.png AppDir/pocketsearchengine.png

# Create AppRun script
echo "Creating AppRun script..."
cat > AppDir/AppRun << EOF
#!/bin/bash
HERE=\$(dirname \$(readlink -f "\${0}"))
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/bin/lib:\${LD_LIBRARY_PATH}"
cd "\${HERE}/usr/bin"
exec "./offline_engine" "\$@"
EOF

chmod +x AppDir/AppRun

# Create symlinks for desktop integration
ln -sf pocketsearchengine.desktop AppDir/.DirIcon
ln -sf pocketsearchengine.png AppDir/.DirIcon

# Download appimagetool if not present
if [ ! -f appimagetool-x86_64.AppImage ]; then
    echo "Downloading appimagetool..."
    wget "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool-x86_64.AppImage
fi

# Create the AppImage
echo "Creating AppImage..."
ARCH=x86_64 ./appimagetool-x86_64.AppImage --appimage-extract-and-run AppDir/ PocketSearchEngine-x86_64.AppImage

# Cleanup
echo "Cleaning up..."
rm -rf AppDir

echo "Done! AppImage created as PocketSearchEngine-x86_64.AppImage" 