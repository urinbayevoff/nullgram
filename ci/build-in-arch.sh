#!/bin/sh
# Runs inside an Arch Linux ARM container (the base ztOS is made from): builds the packages missing from
# out/ (nullgram-tdlib only when its version is not there yet: it takes long), then the pacman repository
# database. makepkg will not run as root: a user of its own does the building.
#   ci/build-in-arch.sh        (out/ holds what the repo release already has)
set -eu
sed -i 's/^DownloadUser/#DownloadUser/; s/^CheckSpace/#CheckSpace/' /etc/pacman.conf
pacman-key --init >/dev/null
pacman-key --populate archlinuxarm >/dev/null
pacman -Rdd --noconfirm linux-aarch64 >/dev/null 2>&1 || true	# no boot files in a container
for try in 1 2 3 4; do	# mirrors drop files now and then
	pacman -Syu --noconfirm --needed base-devel git cmake gperf perl >/dev/null && break
	[ "$try" = 4 ] && exit 1
	sleep $((try * 30))
done
useradd -m builder 2>/dev/null || true
mkdir -p out
chown -R builder: . 

ver() { (. "packaging/arch/$1/PKGBUILD"; echo "$pkgver-$pkgrel"); }
td=$(ver nullgram-tdlib)
if ls out/nullgram-tdlib-"$td"-aarch64.pkg.tar.* >/dev/null 2>&1; then
	echo "nullgram-tdlib $td: already built"
else
	su builder -c "cd packaging/arch/nullgram-tdlib && NULLGRAM_TD_JOBS=$(nproc) PKGDEST=$PWD/out makepkg --noconfirm"
fi
rm -f out/nullgram-[0-9]*.pkg.tar.*		# the app itself: always this commit's
su builder -c "cd packaging/arch/nullgram && NULLGRAM_SRC=$PWD PKGDEST=$PWD/out \
	NULLGRAM_API_ID='${NULLGRAM_API_ID:-}' NULLGRAM_API_HASH='${NULLGRAM_API_HASH:-}' makepkg -d --noconfirm"

# the repository: only the newest of each package, its database as plain files (a release has no links)
cd out
rm -f nullgram.db* nullgram.files*
repo-add -q nullgram.db.tar.gz $(ls -t nullgram-tdlib-*.pkg.tar.* | head -1) $(ls -t nullgram-[0-9]*.pkg.tar.* | head -1)
for f in db files; do rm -f "nullgram.$f"; cp "nullgram.$f.tar.gz" "nullgram.$f"; done
ls -la
