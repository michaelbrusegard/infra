{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    clang
    cmake
    lldb
    llvmPackages.llvm
    llvmPackages.lld
  ];
}
