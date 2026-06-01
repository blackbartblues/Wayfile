# Maintainer: Your Name <your@email.com>
pkgname=heimdall-git
pkgver=r198.g53be041
pkgrel=1
pkgdesc="A lightweight Qt6/QML file manager for Hyprland"
arch=('x86_64' 'aarch64')
url="https://github.com/blackbartblues/Heimdall"
license=('MIT')
depends=(
    'glib2'
    'kwindowsystem'
    'qt6-base'
    'qt6-declarative'
    'qt6-svg'
    'qt6-wayland'
    'fd'
    'xdg-utils'
)
makedepends=(
    'cmake'
    'ninja'
    'git'
    'kwindowsystem'
    'qt6-base'
    'qt6-declarative'
    'qt6-svg'
)
optdepends=(
    'wl-clipboard: clipboard support via wl-copy and wl-paste'
    'bat: syntax-highlighted text previews'
    'gvfs: remote filesystem support via gio/gvfs (sftp, ftp, dav, etc.)'
    'gvfs-smb: SMB/CIFS remote browsing support'
    'ffmpeg: video thumbnails and audio/video metadata (via ffprobe)'
    'poppler: PDF thumbnails, previews, and metadata (via pdftoppm/pdfinfo)'
    'perl-image-exiftool: EXIF metadata for images (via exiftool)'
    'udisks2: mount/unmount devices from sidebar'
)
provides=('heimdall')
conflicts=('heimdall')
source=(
    "${pkgname}::git+https://github.com/blackbartblues/Heimdall.git"
    "quill-icons::git+https://github.com/soyeb-jim285/quill-icons.git"
    "quill::git+https://github.com/soyeb-jim285/quill.git"
)
sha256sums=('SKIP' 'SKIP' 'SKIP')

pkgver() {
    cd "${pkgname}"
    printf "r%s.g%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

prepare() {
    cd "${pkgname}"
    git submodule init
    git config submodule.src/qml/icons.url "${srcdir}/quill-icons"
    git config submodule.src/qml/Quill.url "${srcdir}/quill"
    git -c protocol.file.allow=always submodule update
}

build() {
    cmake -B build -S "${pkgname}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TESTS=OFF \
        -DHEIMDALL_DATA_DIR=/usr/share/heimdall
    cmake --build build --parallel
}

package() {
    # Install the compiled binary
    install -Dm755 "build/src/heimdall" "${pkgdir}/usr/bin/heimdall"

    # Install themes — loaded via applicationDirPath()/../themes → /usr/share/heimdall/themes
    install -dm755 "${pkgdir}/usr/share/heimdall/themes"
    install -Dm644 "${pkgname}/themes/"*.toml \
        -t "${pkgdir}/usr/share/heimdall/themes/"

    # Install QML module metadata (needed for loadFromModule to find Heimdall)
    install -Dm644 "build/src/Heimdall/qmldir" \
        "${pkgdir}/usr/share/heimdall/Heimdall/qmldir"
    install -Dm644 "build/src/Heimdall/heimdall.qmltypes" \
        "${pkgdir}/usr/share/heimdall/Heimdall/heimdall.qmltypes" 2>/dev/null || true

    # Install QML sources for Quill module
    install -dm755 "${pkgdir}/usr/share/heimdall/src"
    cp -r "${pkgname}/src/qml" "${pkgdir}/usr/share/heimdall/src/qml"

    # Install desktop entry, icon and AppStream metainfo
    install -Dm644 "${pkgname}/dist/io.github.blackbartblues.Heimdall.desktop" \
        "${pkgdir}/usr/share/applications/io.github.blackbartblues.Heimdall.desktop"
    install -Dm644 "${pkgname}/dist/io.github.blackbartblues.Heimdall.svg" \
        "${pkgdir}/usr/share/icons/hicolor/scalable/apps/io.github.blackbartblues.Heimdall.svg"
    install -Dm644 "${pkgname}/dist/io.github.blackbartblues.Heimdall.metainfo.xml" \
        "${pkgdir}/usr/share/metainfo/io.github.blackbartblues.Heimdall.metainfo.xml"

    # Install license
    install -Dm644 "${pkgname}/LICENSE" \
        "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
