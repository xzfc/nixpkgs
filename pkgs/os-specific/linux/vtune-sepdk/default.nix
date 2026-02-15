{
  bash,
  coreutils,
  getent,
  gnugrep,
  gnused,
  intel-oneapi-vtune,
  kernel,
  kmod,
  lib,
  makeWrapper,
  p7zip,
  procps,
  python3,
  shadow,
  stdenv,
  su,
  which,
}:

let
  binPath = lib.makeBinPath [
    bash
    coreutils
    getent
    gnugrep
    gnused
    kmod
    procps
    python3
    shadow
    su
    which
  ];
  libexecDir = "\${out}/libexec/vtune-sepdk";
  modDestDir = "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/platform/x86";
in
stdenv.mkDerivation {
  pname = "vtune-sepdk";
  version = "${intel-oneapi-vtune.version}-${kernel.version}";

  inherit (intel-oneapi-vtune) src;

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = [
    makeWrapper
    p7zip
    which
  ]
  ++ kernel.moduleBuildDependencies;

  makeFlags = [
    "INSTALL=${libexecDir}"

    # These should be set by `src/build-driver`. But we use `make` directly.
    "KERNEL_SRC_DIR=${kernel.dev}/lib/modules/${kernel.version}/build"
    "KERNEL_VERSION=${kernel.version}" # `uname -r`
    "SEP_DRIVERS_ONLY=0"
    "VERBOSE=1"

    # If these not set, the Makefile will try to run `uname`.
    "MACH=x86_64" # `uname -m`
    "SMP=1" # `uname -v | grep SMP`
  ];

  unpackPhase = ''
    runHook preUnpack
    7za x $src _installdir/vtune/${intel-oneapi-vtune.version}/sepdk
    cd _installdir/vtune/${intel-oneapi-vtune.version}/sepdk/src
    runHook postUnpack
  '';

  preBuild = ''
    makeFlags="$makeFlags CC=$(which $CC)"
  '';

  prePatch = ''
    # In systemd units, /dev/stderr is a symlink to a socket.
    # Consequently, the line `echo "$MSG" >> /dev/stderr` in these scripts fail.
    substituteInPlace \
        ./rmmod-sep \
        pax/boot-script \
        pax/insmod-pax \
        pax/rmmod-pax \
        socwatch/insmod-socwatch \
        socwatch/rmmod-socwatch \
        vtsspp/insmod-vtsspp \
        vtsspp/rmmod-vtsspp \
      --replace-fail 'if [ -w /dev/stderr ] ; then' \
                     'if false ; then'

    patchShebangs socwatch/build_drivers.sh
  '';

  preInstall = "mkdir -p ${libexecDir}";

  postInstall = ''
    # Install wrappers to bin, prefixed with `sepdk-`.
    for i in \
      ./insmod-sep \
      ./rmmod-sep \
      pax/insmod-pax \
      pax/rmmod-pax \
      socwatch/insmod-socwatch \
      socwatch/rmmod-socwatch \
      vtsspp/insmod-vtsspp \
      vtsspp/rmmod-vtsspp
    do
      sed -i "s/^PATH=/# &/" ${libexecDir}/$i
      makeWrapper ${libexecDir}/$i $out/bin/sepdk-''${i##*/} --set PATH "${binPath}"
    done
  '';

  meta = {
    description = "Kernel module for Intel VTune Profiler";
    homepage = "https://www.intel.com/content/www/us/en/docs/vtune-profiler/user-guide/2024-0/sep-driver.html";
    license = [
      lib.licenses.bsd3
      lib.licenses.gpl2Only
      lib.licenses.unfree
    ];
    maintainers = [
      lib.maintainers.xzfc
    ];
    platforms = [ "x86_64-linux" ];
  };
}
