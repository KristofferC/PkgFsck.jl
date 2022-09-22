module PkgFsck

export fsck_packages, redownload, fsck_artifacts

using Downloads
using Pkg
import Pkg: Registry
using Tar
using CoverageTools

struct PkgFsckFailure
    local_path::String
    uuid::Base.UUID
    tree_hash::Base.SHA1
    has_build_file::Bool
end

function redownload(fail::PkgFsckFailure)
    rm(fail.local_path; recursive=true, force=true)
    server = Pkg.pkg_server()
    url = "$server/package/$(fail.uuid)/$(fail.tree_hash)"
    tmp = Downloads.download(url)
    Tar.extract(`$(Pkg.PlatformEngines.exe7z()) x $tmp -so`, fail.local_path)
    rm(tmp)
    return
end


function fsck_packages(; remove_cov_files::Bool=true, depot_path::Vector{String}=DEPOT_PATH)
    failed_packages = PkgFsckFailure[]
    registries = Pkg.Registry.reachable_registries()
    for reg in registries
        for (_, pkg) in reg
            fsck_package!(failed_packages, pkg; remove_cov_files, depot_path)
        end
    end
    return failed_packages
end

function fsck_package!(failed_packages::AbstractVector{PkgFsckFailure}, pkg::Registry.PkgEntry;
                       remove_cov_files::Bool, depot_path::Vector{String})
    pkginfo = Registry.registry_info(pkg)
    for (v, vinfo) in pkginfo.version_info
        tree_hash = vinfo.git_tree_sha1
        for slug in (Base.version_slug(pkg.uuid, tree_hash), Base.version_slug(pkg.uuid, tree_hash, 4))
            for depot in depot_path
                path = joinpath(depot, "packages", pkg.name, slug)
                isdir(path) || continue

                # Check package
                has_build_file = isdir(joinpath(path, "deps"))
                if Base.SHA1(Pkg.GitTools.tree_hash(path)) !== tree_hash
                    if remove_cov_files
                        try
                            CoverageTools.clean_folder(path)
                        catch
                            @error "Coverage cleaning failed in $path"
                        end
                        # Cleaning cov files fixed it
                        if Base.SHA1(Pkg.GitTools.tree_hash(path)) == tree_hash
                            continue
                        end
                    end
                    fail = PkgFsckFailure(path, pkg.uuid, tree_hash, has_build_file)
                    push!(failed_packages, fail)
                end
            end
        end
    end
    return failed_packages
end


struct ArtifactFsckFailure
    local_path::String
end

function redownload(fail::ArtifactFsckFailure)
    rm(fail.local_path; recursive=true, force=true)
    server = Pkg.pkg_server()
    hash = basename(fail.local_path)
    url = "$server/artifact/$hash"
    tmp = Downloads.download(url)
    Tar.extract(`$(Pkg.PlatformEngines.exe7z()) x $tmp -so`, fail.local_path)
    rm(tmp)
    return
end

function fsck_artifacts()
    failed_artifacts = ArtifactFsckFailure[]
    for depot in DEPOT_PATH
        artifacts_dir = joinpath(depot, "artifacts")
        isdir(artifacts_dir) || continue
        for sha in readdir(artifacts_dir)
            artifact_dir = joinpath(artifacts_dir, sha)
            isdir(artifact_dir) || continue
            if  Base.SHA1(Pkg.GitTools.tree_hash(artifact_dir)) != Base.SHA1(sha)
                push!(failed_artifacts, ArtifactFsckFailure(artifact_dir))
            end
        end
    end
    return failed_artifacts
end

end # module PkgFsck
