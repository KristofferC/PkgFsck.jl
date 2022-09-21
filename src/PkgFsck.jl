module PkgFsck

export fsck, redownload

using Downloads
using Pkg
import Pkg: Registry
using Tar
using CoverageTools

struct FsckFailure
    local_path::String
    uuid::Base.UUID
    tree_hash::Base.SHA1
    has_build_file::Bool
end

function redownload(fail::FsckFailure)
    rm(fail.local_path; recursive=true, force=true)
    server = Pkg.pkg_server()
    url = "$server/package/$(fail.uuid)/$(fail.tree_hash)"
    tmp = Downloads.download(url)
    Tar.extract(`$(Pkg.PlatformEngines.exe7z()) x $tmp -so`, fail.local_path)
    rm(tmp)
    return
end


function fsck(; remove_cov_files::Bool=true)
    failed_packages = FsckFailure[]
    registries = Pkg.Registry.reachable_registries()
    for reg in registries
        for (_, pkg) in reg
            fsck_package!(failed_packages, pkg; remove_cov_files)
        end
    end
    return failed_packages
end

function fsck_package!(failed_packages::AbstractVector{FsckFailure}, pkg::Registry.PkgEntry; remove_cov_files::Bool)
    pkginfo = Registry.registry_info(pkg)
    for (v, vinfo) in pkginfo.version_info
        tree_hash = vinfo.git_tree_sha1
        for slug in (Base.version_slug(pkg.uuid, tree_hash), Base.version_slug(pkg.uuid, tree_hash, 4))
            for depot in DEPOT_PATH
                path = joinpath(depot, "packages", pkg.name, slug)
                if ispath(path)
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
                        fail = FsckFailure(path, pkg.uuid, tree_hash, has_build_file)
                        push!(failed_packages, fail)
                    end
                end
            end
        end
    end
    return failed_packages
end

end # module PkgFsck
