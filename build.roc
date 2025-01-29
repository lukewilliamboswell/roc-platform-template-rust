app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.19.0/Hj-J_zxz7V9YurCSTFcFdu6cQJie4guzsPMUi5kBYUk.tar.br",
    weaver: "https://github.com/smores56/weaver/releases/download/0.6.0/4GmRnyE7EFjzv6dDpebJoWWwXV285OMt4ntHIc6qvmY.tar.br",
}

import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import weaver.Opt
import weaver.Cli

## Builds the [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc
##
## Check basic-cli-build-steps.png for a diagram that shows what the code does.
##
main! = |args|

    cli_parser =
        { Cli.weave <-
            debug_mode: Opt.flag({ short: "d", long: "debug", help: "Runs `cargo build` without `--release`." }),
            maybe_roc: Opt.maybe_str({ short: "r", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path." }),
        }
        |> Cli.finish(
            {
                name: "basic-cli-builder",
                version: "",
                authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
                description: "Generates all files needed by Roc to use this basic-cli platform.",
            },
        )
        |> Cli.assert_valid

    run!(Cli.parse_or_display_message(cli_parser, args, Arg.to_os_raw) ? |msg| Err(ErrParsingArgs msg))

run! : { debug_mode : Bool, maybe_roc : Result Str err } => Result {} _
run! = |{ debug_mode, maybe_roc }|
    # rocCmd may be a path or just roc
    roc_cmd = maybe_roc ?? "roc"

    roc_version!(roc_cmd)?

    os_and_arch = get_os_and_arch!({})?

    stub_lib_path = "platform/libapp.${stub_file_extension(os_and_arch)}"

    build_stub_app_lib!(roc_cmd, stub_lib_path)?

    cargo_build_host!(debug_mode)?

    rust_target_folder = get_rust_target_folder!(debug_mode)?

    copy_host_lib!(os_and_arch, rust_target_folder)?

    preprocess_host!(roc_cmd, stub_lib_path, rust_target_folder)?

    info!("Successfully built platform files!")?

    Ok({})

roc_version! : Str => Result {} _
roc_version! = |roc_cmd|
    info!("Checking provided roc; executing `${roc_cmd} version`:")?

    Cmd.exec!(roc_cmd, ["version"]) ? RocVersionCheckFailed

    Ok({})

get_os_and_arch! : {} => Result OSAndArch _
get_os_and_arch! = |{}|
    info!("Getting the native operating system and architecture ...")?

    convert_os_and_arch(Env.platform!({}))

OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convert_os_and_arch : _ -> Result OSAndArch _
convert_os_and_arch = |{ os, arch }|
    when (os, arch) is
        (MACOS, AARCH64) -> Ok(MacosArm64)
        (MACOS, X64) -> Ok(MacosX64)
        (LINUX, AARCH64) -> Ok(LinuxArm64)
        (LINUX, X64) -> Ok(LinuxX64)
        _ -> Err(UnsupportedNative(os, arch))

build_stub_app_lib! : Str, Str => Result {} _
build_stub_app_lib! = |roc_cmd, stub_lib_path|
    info!("Building stubbed app shared library ...")?

    Cmd.exec!(roc_cmd, ["build", "--lib", "platform/stub.roc", "--output", stub_lib_path, "--optimize"]) ? ErrBuildingAppStub

    Ok({})

stub_file_extension : OSAndArch -> Str
stub_file_extension = |os_and_arch|
    when os_and_arch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64 -> "so"
        WindowsX64 | WindowsArm64 -> "dll"

prebuilt_static_lib_file : OSAndArch -> Str
prebuilt_static_lib_file = |os_and_arch|
    when os_and_arch is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

get_rust_target_folder! : Bool => Result Str _
get_rust_target_folder! = |debug_mode|
    debug_or_release =
        if debug_mode then
            "debug"
        else
            "release"

    when Env.var!("CARGO_BUILD_TARGET") is
        Ok(target_env_var) ->
            if Str.is_empty(target_env_var) then
                Ok("target/${debug_or_release}/")
            else
                Ok("target/${target_env_var}/${debug_or_release}/")

        Err(e) ->
            info!("Failed to get env var CARGO_BUILD_TARGET with error ${Inspect.to_str(e)}. Assuming default? CARGO_BUILD_TARGET (native)...")?

            Ok("target/${debug_or_release}/")

cargo_build_host! : Bool => Result {} _
cargo_build_host! = |debug_mode|

    if debug_mode then
        info!("Building rust host in debug mode...")?
    else
        info!("Building rust host ...")?

    cargo_build_args_t =
        if debug_mode then
            ["build"]
        else
            ["build", "--release"]

    Cmd.exec!("cargo", cargo_build_args_t) ? ErrBuildingHostBinaries

    Ok({})

copy_host_lib! : OSAndArch, Str => Result {} _
copy_host_lib! = |os_and_arch, rust_target_folder|
    host_build_path =
        "${rust_target_folder}libhost.a"

    host_dest_path = "platform/${prebuilt_static_lib_file(os_and_arch)}"

    info!("Moving the prebuilt binary from ${host_build_path} to ${host_dest_path} ...")?

    Cmd.exec!("cp",[host_build_path, host_dest_path]) ? ErrMovingPrebuiltLegacyBinary

    Ok({})

preprocess_host! : Str, Str, Str => Result {} _
preprocess_host! = |roc_cmd, stub_lib_path, rust_target_folder|

    info!("Preprocessing surgical host ...")?

    surgical_build_path = "${rust_target_folder}host"

    Cmd.exec!(roc_cmd, ["preprocess-host", surgical_build_path, "platform/main.roc", stub_lib_path]) ? ErrPreprocessingSurgicalBinary

    Ok({})

info! : Str => Result {} _
info! = |msg|
    Stdout.line!("\u(001b)[34mINFO:\u(001b)[0m ${msg}")
