"""Boost headers extracted in a build action.

The Boost release archive is 190MB compressed and over a gigabyte extracted,
nearly all of it sources, docs and tools that a headers-only dependency never
reads. Extracting it in the repository rule cost every fresh output base close
to a minute of Bazel's Java extractor before analysis could complete.

The module source is the (sub-megabyte) Boost superproject tag; the release
archive is only downloaded by a repository rule and the `boost/` header tree
is extracted from it by a build action with the hermetic bsdtar from the
tar.bzl toolchain. The action is cached on the archive digest and, with remote
execution, the extracted tree only ever lives on the workers.
"""

TAR_TOOLCHAIN_TYPE = "@tar.bzl//tar/toolchain:type"

BOOST_VERSION = "1.89.0"

BOOST_ARCHIVE = struct(
    url = "https://archives.boost.io/release/{v}/source/boost_{u}.tar.gz".format(
        v = BOOST_VERSION,
        u = BOOST_VERSION.replace(".", "_"),
    ),
    sha256 = "9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93",
    filename = "boost_{}.tar.gz".format(BOOST_VERSION.replace(".", "_")),
    strip_prefix = "boost_{}".format(BOOST_VERSION.replace(".", "_")),
)

def _archive_repository_impl(ctx):
    ctx.download(
        url = ctx.attr.url,
        output = ctx.attr.filename,
        sha256 = ctx.attr.sha256,
    )
    ctx.file("WORKSPACE", 'workspace(name = "{}")\n'.format(ctx.name))
    ctx.file("BUILD.bazel", 'exports_files(["{}"])\n'.format(ctx.attr.filename))

_archive_repository = repository_rule(
    implementation = _archive_repository_impl,
    attrs = {
        "filename": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "url": attr.string(mandatory = True),
    },
    doc = "Downloads the Boost release archive; it is extracted by a build action.",
)

def _archive_impl(_module_ctx):
    _archive_repository(
        name = "boost_headers_archive",
        filename = BOOST_ARCHIVE.filename,
        sha256 = BOOST_ARCHIVE.sha256,
        url = BOOST_ARCHIVE.url,
    )

archive = module_extension(
    implementation = _archive_impl,
    doc = "The repository holding the downloaded Boost release archive.",
)

def _extract_headers_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.directory)
    bsdtar = ctx.toolchains[TAR_TOOLCHAIN_TYPE]
    prefix = ctx.attr.strip_prefix.strip("/")
    args = ctx.actions.args()
    args.add("--extract")
    args.add("--file", ctx.file.archive)
    args.add("-C", out.dirname)
    args.add("--strip-components", str(len(prefix.split("/")) if prefix else 0))
    args.add("{}/{}".format(prefix, ctx.attr.directory) if prefix else ctx.attr.directory)
    ctx.actions.run(
        executable = bsdtar.tarinfo.binary,
        inputs = depset([ctx.file.archive], transitive = [bsdtar.default.files]),
        outputs = [out],
        arguments = [args],
        mnemonic = "BoostExtractHeaders",
        progress_message = "Extracting Boost headers from %s" % ctx.file.archive.short_path,
        toolchain = TAR_TOOLCHAIN_TYPE,
    )
    return [DefaultInfo(files = depset([out]))]

extract_headers = rule(
    implementation = _extract_headers_impl,
    attrs = {
        "archive": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The Boost release archive.",
        ),
        "directory": attr.string(
            default = "boost",
            doc = "The directory of the archive (after strip_prefix) to extract, and the name of the output tree.",
        ),
        "strip_prefix": attr.string(
            doc = "Directory prefix to strip from the archive members.",
        ),
    },
    toolchains = [TAR_TOOLCHAIN_TYPE],
    doc = "Extracts the `boost/` header tree from the release archive into a tree artifact.",
)
