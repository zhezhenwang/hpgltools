VERSION="201708"
export _R_CHECK_FORCE_SUGGESTS_=FALSE

all: clean roxygen reference check build test

install:
	@echo "Performing R CMD INSTALL hpgltools globally."
	@mv .Rprofile .Rprofile.bak
	R CMD INSTALL .
	@mv .Rprofile.bak .Rprofile

test:
	@echo "Installing hpgltools in the local packrat tree."
	R CMD INSTALL .
	@echo "Running run_tests.R"
	tests/testthat.R

inst: roxygen restore install test
	@echo "Restored packrat, regenerated documentation, installed, and tested."

git: snap
	@echo "Snapshotted packrat and pushed to github."
	git commit -a -m 'snapshotted packrat.' && git push

hi:
	@echo "Hello."

packrat_install:
	echo "Installing all packrat packages globally."
	R -e "library(hpgltools); install_packrat_globally()"

restore:
	echo "Restoring packrat."
	R -e "packrat::restore(restart=FALSE)" --args --bootstrap-packrat

snap:
	echo "Snapshotting packrat."
	R -e "packrat::snapshot()"

push:
	echo "Pushing to github."
	git commit -a && git push

deps:
	@echo "Invoking devtools::install_dev_deps()"
	R -e "suppressPackageStartupMessages(suppressMessages(source('http://bioconductor.org/biocLite.R')));\
all = as.data.frame(devtools::dev_package_deps('.', dependencies=TRUE)); needed = all[['diff']] < 0; needed = all[needed, 'package']; for (t in needed) { biocLite(t) }"

dep_push: deps snap
	echo "Setting default commit message and pushing."
	git commit -a -m 'packrat modification.'
	git push

reference:
	@echo "Generating reference manual with R CMD Rd2pdf"
	rm -f inst/doc/reference.pdf
	R CMD Rd2pdf . -o inst/doc/reference.pdf --no-preview

check:
	@echo "Performing check with R CMD check hpgltools"
	export _R_CHECK_FORCE_SUGGESTS_=FALSE && R CMD check . --no-build-vignettes

build:
	@echo "Performing build with R CMD build hpgltools"
	R CMD build .

roxygen:
	@echo "Generating documentation with devtools::document()"
	R -e "suppressPackageStartupMessages(devtools::document())"

vignette:
	@echo "Building vignettes with devtools::build_vignettes()"
	R -e "devtools::build_vignettes()"

document: roxygen vignette reference

clean_vignette:
	rm -f vignettes/*.rda vignettes/*.map vignettes/*.Rdata

vt:	clean_vignette vignette reference install

clean:
	rm -rf hpgltools/
	rm -rf ./..Rcheck
	rm -rf tests/testthat/circos
	rm -rf tests/testthat/excel
	rm -rf tests/testthat/excel_test
	rm -rf tests/testthat/excel_test_sig
	rm -rf tests/testthat/kegg_pathways
	rm -rf tests/testthat/pathview
	rm -rf tests/testthat/pathview_in
	rm -rf tests/testthat/*.pdf
	rm -rf tests/testthat/*.png
	rm -rf tests/testthat/*.xlsx
	rm -rf tests/testthat/*.rda
	rm -rf tests/testthat/*.gff
	rm -rf tests/testthat/*.gb
	rm -rf tests/testthat/*.map
	rm -rf tests/testthat/*.xml
	rm -rf tests/testthat/*.Rdata
	rm -rf vignettes/circos
	rm -rf vignettes/*.gff
	rm -rf vignettes/*.pdf
	rm -rf hpgltools.Rcheck/
	rm -rf hpgltools_${VERSION}.tar.gz

prereq:
	@echo "Checking a few essential prerequisites.(maybe not needed with packrat)"
	R -e "suppressPackageStartupMessages(suppressMessages(source('http://bioconductor.org/biocLite.R')));\
bioc_prereq <- c('pasilla','testthat','roxygen2','Biobase','preprocessCore','devtools','rmarkdown','knitr','ggplot2','data.table','foreach','survival');\
for (req in bioc_prereq) { if (class(try(suppressMessages(eval(parse(text=paste0('library(', req, ')')))))) == 'try-error') { biocLite(req) } } \
## hahaha looks like lisp!"

update_bioc:
	R -e "source('http://bioconductor.org/biocLite.R'); biocLite(); biocLite('BiocUpgrade');"

update:
	R -e "source('http://bioconductor.org/biocLite.R'); biocLite(); library(BiocInstaller); biocValid()"

install_bioconductor:
	R -e "library(hpgltools); bioc_all()"
