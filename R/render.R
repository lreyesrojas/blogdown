#' Build a website
#'
#' Build the site through Hugo, and optionally (re)build R Markdown files.
#'
#' You can use \code{\link{serve_site}()} to preview your website locally, and
#' \code{build_site()} to build the site for publishing. However, if you use a
#' web publishing service like Netlify, you do not need to build the site
#' locally, but can build it on the cloud. See Section 1.7 of the \pkg{blogdown}
#' book for more information:
#' \url{https://bookdown.org/yihui/blogdown/workflow.html}.
#'
#' For R Markdown posts, there are a few possible rendering methods: \code{html}
#' (the default), \code{markdown}, and \code{custom}. The method can be set in
#' the global option \code{blogdown.method} (usually in the
#' \file{\link{.Rprofile}} file), e.g., \code{options(blogdown.method =
#' "custom")}.
#'
#' For the \code{html} method, \file{.Rmd} posts are rendered to \file{.html}
#' via \code{rmarkdown::\link[rmarkdown]{render}()}, which means Markdown is
#' processed through Pandoc. For the \code{markdown} method, \file{.Rmd} is
#' rendered to \file{.md}, which will typically be rendered to HTML later by the
#' site generator such as Hugo.
#'
#' For all rendering methods, a custom R script \file{R/build.R} will be
#' executed if you have provided it under the root directory of the website
#' (e.g. you can compile Rmd to Markdown through
#' \code{knitr::\link[knitr]{knit}()} and build the site via
#' \code{\link{hugo_cmd}()}). The \code{custom} method means it is entirely up
#' to this R script how a website is rendered. The script is executed via
#' command line \command{Rscript "R/build.R"}, which means it is executed in a
#' separate R session. The value of the argument \code{local} is passed to the
#' command line (you can retrieve the command-line arguments via
#' \code{\link{commandArgs}(TRUE)}). For other rendering methods, the R script
#' \file{R/build2.R} (if exists) will be executed after Hugo has built the site.
#' This can be useful if you want to post-process the site.
#'
#' When \code{build_rmd = TRUE}, all Rmd files will be (re)built. You can set
#' the global option \code{blogdown.files_filter} to a function to determine
#' which Rmd files to build when \code{build_rmd = TRUE}. This function takes a
#' vector of Rmd file paths, and should return a subset of these paths to be
#' built. By default, \code{options(blogdown.files_filter = \link{identity}}.
#' You can use \code{blogdown::\link{filter_newfile}}, which means to build new
#' Rmd files that have not been built before, or
#' \code{blogdown::\link{filter_timestamp}} to build Rmd files if their time
#' stamps (modification time) are newer than their output files, or
#' \code{blogdown::\link{filter_md5sum}}, which is more robust in determining if
#' an Rmd file has been modified (hence needs to be rebuilt).
#' @param local Whether to build the website locally. This argument is passed to
#'   \code{\link{hugo_build}()}, and \code{local = TRUE} is mainly for serving
#'   the site locally via \code{\link{serve_site}()}.
#' @param run_hugo Whether to run \code{hugo_build()} after R Markdown files are
#'   compiled.
#' @param build_rmd Whether to (re)build R Markdown files. By default, they are
#'   not built. See \sQuote{Details} for how \code{build_rmd = TRUE} works.
#'   Alternatively, it can take a vector of file paths, which means these files
#'   are to be (re)built. Or you can provide a function that takes a vector of
#'   paths of all R Markdown files under the \file{content/} directory, and
#'   returns a vector of paths of files to be built, e.g., \code{build_rmd =
#'   blogdown::filter_timestamp}. A few aliases are currently provided for such
#'   functions: \code{build_rmd = 'newfile'} is equivalent to \code{build_rmd =
#'   blogdown::filter_newfile}, \code{build_rmd = 'timestamp'} is equivalent to
#'   \code{build_rmd = blogdown::filter_timestamp}, and \code{build_rmd =
#'   'md5sum'} is equivalent to \code{build_rmd = blogdown::filter_md5sum}.
#' @param ... Other arguments to be passed to \code{\link{hugo_build}()}.
#' @export
build_site = function(local = FALSE, run_hugo = TRUE, build_rmd = FALSE, ...) {
  knitting = is_knitting() || preview_mode()
  if (!knitting) on.exit(run_script('R/build.R', as.character(local)), add = TRUE)
  if (build_method() == 'custom') return()

  if (!isFALSE(build_rmd)) {
    if (is.character(build_rmd) && length(build_rmd) == 1) {
      build_rmd = switch(
        build_rmd, timestamp = filter_timestamp, md5sum = filter_md5sum,
        newfile = filter_newfile, build_rmd
      )
    }
    files = if (is.character(build_rmd)) build_rmd else {
      files = list_rmds(check = TRUE)
      if (is.function(build_rmd)) build_rmd(files) else {
        if (length(files)) get_option('blogdown.files_filter', identity)(files)
      }
    }
    build_rmds(files, knitting)
  }
  if (run_hugo) on.exit(hugo_build(local, ...), add = TRUE)
  if (!knitting) on.exit(run_script('R/build2.R', as.character(local)), add = TRUE)

  invisible()
}

build_method = function() {
  methods = c('html', 'markdown', 'custom')
  match.arg(get_option('blogdown.method', methods), methods)
}

# list and/or filter Rmd file to build
list_rmds = function(
  dir = content_file(), check = FALSE, pattern = rmd_pattern, files = NULL
) {
  if (is.null(files)) files = list_files(dir, pattern)
  # exclude Rmd that starts with _ (preserve these names for, e.g., child docs)
  # but include _index.Rmd/.md
  files = files[!grepl('^_', basename(files)) | grepl('^_index[.]', basename(files))]
  # exclude Rmd within packrat / renv library
  files = files[!grepl('(^|/)(?:packrat|renv)/', files)]
  # do not allow special characters in filenames so dependency names are more
  # predictable, e.g. foo_files/
  if (check) bookdown:::check_special_chars(files)
  files
}

# list .md files
list_mds = function() list_files(content_file(), '[.]md$')

# whether a document is knitted via the Knit button
is_knitting = function() isTRUE(opts$get('render_one'))

# build R Markdown posts
build_rmds = function(files, knitting = is_knitting()) {
  # emit a message indicating that a file is being knitted when the knitting is
  # not triggered by the Knit button
  msg_knit = function(f, start = TRUE) {
    if (knitting) return()
    if (start) {
      message('Rendering ', f, '... ', appendLF = FALSE)
    } else message('Done.')
  }
  # try to make absolute paths to relative
  i = xfun::is_abs_path(files)
  files[i] = rel_path(files[i])

  i = xfun::is_sub_path(files, rel_path(content_file()))
  # use rmarkdown::render() when a file is outside the content/ dir
  for (f in files[!i]) {
    msg_knit(f)
    render_new(f, !knitting)
    msg_knit(f, FALSE)
  }

  if (length(files <- files[i]) == 0) return()
  # ignore files that are locked (being rendered by another process)
  i = !file.exists(locks <- paste0(files, '.lock~'))
  if (!any(i)) return()  # all files are currently being rendered
  files = files[i]
  # remove locks on exit
  file.create(locks <- locks[i]); on.exit(file.remove(locks), add = TRUE)

  # copy by-products {/content/.../foo_(files|cache) dirs and foo.html} from
  # /blogdown/ or /static/ to /content/
  lib1 = by_products(files, c('_files', '_cache'))
  lib2 = gsub('^content', 'blogdown', lib1)  # /blogdown/.../foo_(files|cache)
  i = grep('_files$', lib2)
  lib2[i] = gsub('^blogdown', 'static', lib2[i])  # _files are copied to /static
  # move by-products of a previous run to content/
  dirs_rename(lib2, lib1)

  # move (new) by-products from content/ to blogdown/ or static/ to make the
  # source directory clean
  move_files = function(lib1, lib2) {
    # don't move by-products of leaf bundles
    i = !bundle_index(gsub('_(files|cache)$', '', lib1), ext = FALSE)
    dirs_rename(lib1[i], lib2[i])
  }
  on.exit(move_files(lib1, lib2), add = TRUE)

  base = site_base_dir()
  shared_yml = c('_output.yml', '_bookdown.yml')
  copied_yml = character(); on.exit(unlink(copied_yml), add = TRUE)

  copy_output_yml = function(to) {
    to = file.path(to, shared_yml)
    i = file.copy(shared_yml, to)
    # delete successfully copied .yml files later
    copied_yml <<- c(copied_yml, to[i])
  }

  for (i in seq_along(files)) {
    f = files[i]; d = dirname(f); out = output_file(f)
    to_md = file_ext(out) != 'html'
    out2 = paste0(out, '~')  # first generate a file with ~ in ext so Hugo won't watch
    copy_output_yml(d)
    msg_knit(f)
    x = xfun::Rscript_call(
      build_one, list(f, I(basename(out2)), to_md, !knitting),
      fail = c('Failed to render ', f)
    )

    x = encode_paths(x, lib1[2 * i - 1], d, base, to_md, out)
    move_files(lib1[2 * i - 0:1], lib2[2 * i - 0:1])

    # when serving the site, pause for a moment so Hugo server's auto navigation
    # can navigate to the output page
    if (length(opts$get('served_dirs')) || knitting) {
      server_wait()
    }

    if (get_option('blogdown.widgetsID', TRUE)) x = clean_widget_html(x)
    write_utf8(x, out)
    msg_knit(f, FALSE)
  }
}

build_one = function(input, output, to_md = file_ext(output) != 'html', quiet = TRUE) {
  options(htmltools.dir.version = FALSE, rmarkdown.knit.ext = 'md~')
  setwd(dirname(input))
  input = basename(input)
  # for bookdown's theorem environments generated from bookdown:::eng_theorem
  if (to_md) options(bookdown.output.markdown = TRUE)
  res = rmarkdown::render(
    input, 'blogdown::html_page', output_file = output, envir = globalenv(),
    quiet = quiet, run_pandoc = !to_md, clean = !to_md
  )
  x = read_utf8(res)
  if (to_md) x = process_markdown(res, x)
  unlink(res)
  x
}

process_markdown = function(res, x = read_utf8(res)) {
  unlink(attr(res, 'intermediates'))
  # write HTML dependencies to the body of Markdown
  if (length(meta <- attr(res, 'knit_meta'))) {
    m = rmarkdown:::html_dependencies_as_string(meta, attr(res, 'files_dir'), '.')
    if (length(i <- grep('^---\\s*$', x)) >= 2) {
      x = append(x, m, i[2])
    } else warning(
      'Cannot find the YAML metadata in the .markdown output file. ',
      'HTML dependencies will not be rendered.'
    )
  }
  # resolve bookdown references (figures, tables, sections, ...)
  x = local({
    f = wd_tempfile('.md~', pattern = 'post'); on.exit(unlink(f), add = TRUE)
    write_utf8(x, f)
    bookdown:::process_markdown(f, 'markdown', NULL, TRUE, TRUE, x, NULL)
  })
  # protect math expressions in backticks
  if (get_option('blogdown.protect.math', TRUE)) x = xfun::protect_math(x)
  # remove the special comments from HTML dependencies
  x = gsub('<!--/?html_preserve-->', '', x)
  # render elements that are not commonly supported by Markdown renderers other
  # than Pandoc, e.g., citations and raw blocks
  if (run_pandoc(x)) {
    # temporary .md files to generate citations
    mds = replicate(2, wd_tempfile('.md~', pattern = 'citation'))
    on.exit(unlink(mds), add = TRUE)
    write_utf8(x, mds[1])
    rmarkdown::pandoc_convert(
      mds[1], from = 'markdown', to = paste(markdown_format(), collapse = ''), output = mds[2],
      options = c('--wrap=preserve', '--preserve-tabs'),
      citeproc = TRUE
    )
    x2 = read_utf8(mds[2])
    # pandoc will escape < and > in shortcodes, and below is a hack to restore them
    if (get_option('blogdown.restore.shortcode', TRUE)) {
      x2 = gsub('^\\{\\{\\\\< ([^ ])', '{{< \\1', x2)
      x2 = gsub('([^ ]) \\\\>\\}\\}$', '\\1 >}}', x2)
    }
    x = c(bookdown:::fetch_yaml(x), '', x2)
  }
  x
}

markdown_format = function() get_option(
  'blogdown.markdown.format',
  c('gfm', if (rmarkdown::pandoc_available('2.10.1')) c('+tex_math_dollars', '+footnotes'))
)

run_pandoc = function(x) {
  !is.null(get_option('blogdown.markdown.format')) ||
    length(grep('^(references|bibliography):($| )', x)) ||
    length(grep('[`]{1,}\\{=[[:alnum:]]+}', x))
}

# given the content of a .html file: replace content/*_files/figure-html with
# /*_files/figure-html since this dir will be moved to /static/, and move the
# rest of dirs under content/*_files/ to /static/rmarkdown-libs/ (HTML
# dependencies), so all posts share the same libs (otherwise each post has its
# own dependencies, and there will be a lot of duplicated libs when HTML widgets
# are used extensively in a website)

# example values of arguments: x = <html> code; deps = '2017-02-14-foo_files';
# parent = 'content/post'; output = 'content/post/hello.md'
encode_paths = function(x, deps, parent, base = '/', to_md = FALSE, output) {
  if (!dir_exists(deps)) return(x)  # no external dependencies such as images
  if (!grepl('/$', parent)) parent = paste0(parent, '/')
  deps = basename(deps)
  need_encode = !to_md
  if (need_encode) {
    deps2 = encode_uri(deps)  # encode the path and see if it can be found in x
    # on Unix, paths containing multibyte chars are always encoded by Pandoc
    if (need_encode <- !is_windows() || any(grepl(deps2, x, fixed = TRUE))) deps = deps2
  }
  # find the dependencies referenced in HTML
  r = paste0('(<img src|<script src|<link href)(=")(', deps, '/)')

  # for bundle index pages, add {{< blogdown/postref >}} to URLs, to make sure
  # the post content can be displayed anywhere (not limited to the post page,
  # e.g., image paths of a post should also work on the home page if the full
  # post is included on the home page); see the bug report at
  # https://github.com/rstudio/blogdown/issues/501
  if (bundle_index(output)) {
    create_shortcode('postref.html', ref <- 'blogdown/postref')
    return(gsub(r, sprintf('\\1\\2{{< %s >}}\\3', ref), x))
  }

  # move figures to /static/path/to/post/foo_files/figure-html
  if (FALSE) {
    # this is a little more rigorous: the approach below ("\'?)(%s/figure-html/)
    # means process any paths that "seems to have been generated from Rmd"; the
    # optional single quote after double quote is only for the sake of
    # trelliscopejs, where the string may be "'*_files/figure-html'"
    r1 = paste0(r, '(figure-html/)')
    x = gsub(r1, paste0('\\1\\2', gsub('^content/', base, parent), '/\\3\\4'), x)
  }
  r1 = sprintf('("\'?)(%s/figure-html/)', deps)
  x = gsub(r1, paste0('\\1', gsub('^content/', base, parent), '\\2'), x, perl = TRUE)
  # move other HTML dependencies to /static/rmarkdown-libs/
  r2 = paste0(r, '([^/]+)/')
  x2 = grep(r2, x, value = TRUE)
  if (length(x2) == 0) return(x)
  libs = unique(gsub(r2, '\\3\\4', unlist(regmatches(x2, gregexpr(r2, x2)))))
  libs = file.path(parent, if (need_encode) decode_uri(libs) else libs)
  x = gsub(r2, sprintf('\\1\\2%srmarkdown-libs/\\4/', base), x)
  to = file.path('static', 'rmarkdown-libs', basename(libs))
  dirs_rename(libs, to, clean = TRUE)
  x
}

create_shortcode = function(from, to) in_root({
  to = sprintf('layouts/shortcodes/%s.html', to)
  dir_create(dirname(to))
  from = pkg_file('resources', from)
  file.copy(from, to, overwrite = TRUE)
})
