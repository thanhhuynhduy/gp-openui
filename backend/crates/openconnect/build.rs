use std::{env, path::PathBuf, process::Command};

fn apply_patches(patches_dir: &PathBuf, build_src: &PathBuf) {
  let patches = std::fs::read_dir(patches_dir)
    .expect("Failed to read patches directory")
    .filter_map(|entry| entry.ok())
    .filter(|entry| entry.path().extension().and_then(|s| s.to_str()) == Some("patch"))
    .map(|entry| entry.path())
    .collect::<Vec<_>>();

  // Sort patches to ensure they are applied in order
  let mut patches = patches;
  patches.sort();

  for patch in patches {
    println!("cargo:rerun-if-changed={}", patch.display());
    println!("Applying patch: {}", patch.display());

    let status = Command::new("patch")
      .arg("-p1") // Strip one level of path (standard for git diffs)
      .arg("-i") // Input file
      .arg(&patch)
      .current_dir(build_src) // Run INSIDE the copied dir
      .status()
      .expect("Failed to execute patch command");

    if !status.success() {
      panic!("Failed to apply patch file: {}", patch.display());
    }
  }
}

fn build_openconnect(deps_dir: &PathBuf, out_dir: &PathBuf) -> PathBuf {
  let openconnect_dir = deps_dir.join("openconnect");
  let patches_dir = deps_dir.join("patches");

  // The temporary location where we will build
  let build_src = out_dir.join("openconnect_build");

  // Track changes so cargo rebuilds if patch or submodule changes
  println!("cargo:rerun-if-changed={}", openconnect_dir.display());

  // Prepare the build directory
  // If the directory exists from a previous run, remove it to ensure a clean slate
  if build_src.exists() {
    std::fs::remove_dir_all(&build_src).unwrap();
  }
  std::fs::create_dir_all(&build_src).unwrap();

  // Copy the source code to OUT_DIR
  // We use fs_extra options to copy contents recursively
  let mut options = fs_extra::dir::CopyOptions::new();
  options.overwrite = true;
  options.content_only = true; // Copy content of src into dest, not src folder itself

  fs_extra::dir::copy(&openconnect_dir, &build_src, &options).expect("Failed to copy C source code to OUT_DIR");

  // Apply all patches from the patches directory
  apply_patches(&patches_dir, &build_src);

  // Build the OpenConnect library using autotools
  // We explicitly enable static and disable shared to ensure we get a .a file.
  // .reconf("-ivf") is CRITICAL for git submodules because 'configure'
  // usually doesn't exist yet and needs to be generated.
  let dst = autotools::Config::new(&build_src)
    .reconf("-ivf")
    .enable_static()
    .disable_shared()
    .disable("nls", None) // disable translations to save space
    .disable("docs", None)
    .disable("dsa-tests", None)
    .without("libproxy", None)
    .without("stoken", None)
    .without("libpcsclite", None)
    .without("libpskc", None)
    .without("gssapi", None)
    .with("gnutls-tss2", Some("no"))
    .with("vpnc-script", Some("/etc/vpnc/vpnc-script")) // Specify vpnc-script, otherwise it will fail on macOS
    .build();

  let lib_dir = dst.join("lib");
  let include_dir = dst.join("include");

  // Tell rustc where to find the static library
  println!("cargo:rustc-link-search=native={}", lib_dir.display());

  // Static linking of openconnect
  println!("cargo:rustc-link-lib=static=openconnect");

  // Export include path for downstream use (bindgen / cc)
  println!("cargo:include={}", include_dir.display());

  dst
}

fn main() {
  let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
  let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
  let deps_dir = PathBuf::from(manifest_dir).join("deps");

  let oc_dst = build_openconnect(&deps_dir, &out_dir);

  // Using pkg-config to find system deps
  pkg_config::probe_library("libxml-2.0").unwrap();
  pkg_config::probe_library("zlib").unwrap();
  pkg_config::probe_library("liblz4").unwrap();
  pkg_config::probe_library("gnutls").unwrap();

  // Below are required by gnutls
  pkg_config::probe_library("p11-kit-1").unwrap();
  pkg_config::probe_library("hogweed").unwrap();
  pkg_config::probe_library("nettle").unwrap();
  pkg_config::probe_library("gmp").unwrap();

  // Compile the vpn.c file
  println!("cargo:rerun-if-changed=src/ffi/vpn.c");
  println!("cargo:rerun-if-changed=src/ffi/vpn.h");

  // Prevent silent fallback to dynamic libraries
  #[cfg(target_os = "linux")]
  {
    println!("cargo:rustc-link-arg=-Wl,-Bstatic");
    println!("cargo:rustc-link-arg=-Wl,-Bdynamic");
  }

  cc::Build::new()
    .file("src/ffi/vpn.c")
    .include("src/ffi")
    .include(&oc_dst.join("include"))
    .compile("vpn");
}
