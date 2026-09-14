# Link checks against the live web.
#
# Every URL this package puts in front of a reader is verified here: the ones written into
# the README, the manual, the docstrings, the CITATION files and the example scripts, and
# the ones the package assembles at run time from a prefix and an identifier.
#
# The unit suite never leaves the machine, so a link that rots is invisible to it, and the
# integration suite watches the API rather than the prose around it. Two kinds of rot matter
# more than a typo would: a licence URL is what a user follows to decide whether they may
# redistribute a dataset, and the OBIS manual pages carry the data-use conditions the
# package quotes rather than restates.
#
# Like the integration tests, these are not part of the default suite and never run on every
# push. Run them deliberately:
#
#     julia --project=. test/links/runtests.jl
#
# Failures here are external by nature: from a CI runner a single unreachable host is far
# more often a slow server or a rate limit than a dead link, so every URL is retried before
# it is reported, and the scheduled job retries the whole script.

using Test
using HTTP
using OBISClient

const ROOT = dirname(dirname(@__DIR__))

# What is scanned: the files a reader of this package actually sees. `test/` is left out on
# purpose — its fixtures are recorded API payloads, full of third-party URLs the package
# neither publishes nor controls, and a provider's dead homepage is not this package's bug.
const SOURCES = [
    "README.md",
    "CHANGELOG.md",
    "CITATION.cff",
    "CITATION.bib",
    "docs/make.jl",
    "docs/src",
    "src",
    "ext",
    "examples",
]

const EXTENSIONS = (".md", ".jl", ".cff", ".bib")

# Excluded characters are delimiters rather than URL characters: the closing halves of a
# Markdown link, of a BibTeX `\url{}`, of a quoted string in Julia source, of a code span.
const URL_PATTERN = r"(?:https?|ftp)://[^\s<>\"'`()\[\]{}\\|]+"

# Trailing punctuation belongs to the sentence, not to the URL.
const SENTENCE_END = r"[.,;:!?]+$"

# Prefixes the package completes with an identifier before showing them. The bare prefix is
# not a page of its own, so each is checked with a real identifier appended instead.
const TEMPLATES = [
    (
        prefix="https://obis.org/dataset/",
        example="https://obis.org/dataset/8acba7e7-2e50-4490-8328-b78a30472508",
        follow=true,
        note="the dataset page `citation.jl` writes into every BibTeX entry it prints",
    ),
    (
        prefix="https://doi.org/",
        example="https://doi.org/10.1371/journal.pone.0029715",
        follow=false,
        # Checked without following the redirect: what has to hold is that the resolver
        # still answers and still knows an identifier. Where the publisher sends it
        # afterwards is outside this package's control and behind some publishers' bot
        # filtering, which would make a green suite depend on the wrong thing.
        note="the DOI prefix `citation.jl` puts in front of the DOI OBIS reports",
    ),
]

"""
    source_files() -> Vector{String}

Absolute paths of every file under `SOURCES` with a scanned extension.
"""
function source_files()
    files = String[]
    for entry in SOURCES
        path = joinpath(ROOT, entry)
        if isfile(path)
            push!(files, path)
        elseif isdir(path)
            for (dir, _, names) in walkdir(path), name in names
                any(ext -> endswith(name, ext), EXTENSIONS) &&
                    push!(files, joinpath(dir, name))
            end
        end
    end
    return sort!(unique!(files))
end

"""
    urls_in(text) -> Vector{String}

Every HTTP, HTTPS or FTP URL in `text`, stripped of the punctuation that ended the sentence
carrying it.
"""
function urls_in(text::AbstractString)
    return [replace(m.match, SENTENCE_END => "") for m in eachmatch(URL_PATTERN, text)]
end

"""
    reachable(url; follow=true, attempts=3) -> (ok, detail)

Whether `url` answers with a status below 400, and the status or error behind that verdict.

`HEAD` first: the body is never needed and one of these URLs is a multi-megabyte Parquet
file. A server that refuses `HEAD` — 405, and a handful that answer 403 or 404 to it — is
asked again with `GET`. Both are retried, so a slow host is not reported as a dead link.

The `#fragment` is dropped before the request, as a browser does: it names a place in the
page rather than the page, and some servers (GitHub Pages among them) answer 400 to it.
"""
function reachable(url::AbstractString; follow::Bool=true, attempts::Int=3)
    url = first(split(url, '#'; limit=2))
    detail = "no response"
    for attempt in 1:attempts
        attempt > 1 && sleep(5)
        for method in ("HEAD", "GET")
            try
                r = HTTP.request(
                    method,
                    url;
                    headers=["User-Agent" => OBISClient.config().user_agent],
                    status_exception=false,
                    redirect=follow,
                    redirect_limit=10,
                    readtimeout=45,
                    connect_timeout=30,
                    retry=false,
                )
                r.status < 400 && return (true, string(method, " ", r.status))
                detail = string(method, " ", r.status)
            catch e
                detail = sprint(showerror, e)
            end
        end
    end
    return (false, detail)
end

# Where each URL was found, so a failure names the file to fix rather than only the link.
const CITED = Dict{String,Vector{String}}()
const FILES = source_files()
for file in FILES
    for url in urls_in(read(file, String))
        push!(get!(CITED, url, String[]), relpath(file, ROOT))
    end
end
foreach(unique!, values(CITED))

const PREFIXES = Set(t.prefix for t in TEMPLATES)
const LINKS = sort!(filter(!in(PREFIXES), collect(keys(CITED))))

@info "Scanned $(length(FILES)) files" urls = length(LINKS) prefixes = length(TEMPLATES)

const BROKEN = Tuple{String,String}[]

# The report is printed from `finally` because a failing `@testset` throws: without it
# the run would end on Test's own summary, which names the URL but not the status behind
# it nor the file to fix.
try
    @testset "Links" begin
        @testset "$url" for url in LINKS
            ok, detail = reachable(url)
            ok || push!(BROKEN, (url, detail))
            @test ok
        end

        @testset "$(t.prefix)" for t in TEMPLATES
            # A prefix no longer cited anywhere is an exemption that has outlived the
            # link it was written for, and would quietly stop testing anything.
            @test haskey(CITED, t.prefix)

            ok, detail = reachable(t.example; follow=t.follow)
            ok || push!(BROKEN, (t.example, string(detail, " — ", t.note)))
            @test ok
        end
    end
finally
    if isempty(BROKEN)
        println("\nAll $(length(LINKS) + length(TEMPLATES)) links are reachable.")
    else
        println("\n$(length(BROKEN)) unreachable link(s):")
        for (url, detail) in BROKEN
            println("  ", url, "  →  ", detail)
            haskey(CITED, url) && println("    cited in ", join(CITED[url], ", "))
        end
    end
end
