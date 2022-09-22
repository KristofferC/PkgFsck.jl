# PkgFsck.jl

PkgFsck.jl is a package to find corrupted packages and artifacts in depots and fix them.

## Packages

To show how it works we download a package and corrupt it:

```julia
(jl_qgafe7) pkg> add Example

julia> example_path = Base.find_package("Example")
"/home/kc/.julia/packages/Example/aqsx3/src/Example.jl"

julia> touch(joinpath(dirname(example_path), "corruption"))
"/home/kc/.julia/packages/Example/aqsx3/src/corruption"
```

```julia
julia> import PkgFsck

julia> failures = PkgFsck.fsck_packages();

julia> filter!(x->!x.has_build_file, failures) # See Caveats below
1-element Vector{PkgFsck.PkgFsckFailure}:
 PkgFsck.PkgFsckFailure("/home/kc/.julia/packages/Example/aqsx3", UUID("7876af07-990d-54b4-ab0e-23690620f79a"), SHA1("46e44e869b4d90b96bd8ed1fdcf32244fddfb6cc"), false)

julia> foreach(PkgFsck.redownload, failures) # Removes the corrupted folder and redownloads the package
```

### Caveats

#### Build

Packages using the `deps/build.jl` file often give false positives since they
tend to create files into the package directory and there is no way
to know which files are part of the original download. These packages
have the `has_build_file` property set to `true` in the returned
objects of `fsck_packages` allowing them to be filtered out.

#### Coverage files

The coverage system in Julia tend to put `.cov` file into the package
directories. By default, `fsck` will try to clean these out, this can be set
with the `remove_cov_files::Bool` keyword to `fsck`.

## Artifacts

Detecting and fixing corrupted artifacts work in the same way. Run `fsck_artifacts()` and then `redownload` on the items in the returned vector.
