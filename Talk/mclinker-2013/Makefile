# Generic makefile for processing Beamer files
# 
# Rouben Rostamian <rostamian@umbc.edu>
# December 2004

BASE	= mclinker-2013-chenwj

FIGURES = fig/*
DOTS    = dot/*
CODE    = code/*

$(BASE).pdf: $(BASE).tex $(FIGURES) ${DOTS} ${CODE}
	@(\
	AUX=$(BASE).aux; \
	if [ ! -f $$AUX ]; then pdflatex $(BASE); fi; \
	pages1=`sed -n '/inserttotalframenumber/{ s/[^0-9]//g; p; }' < $$AUX`; \
	pdflatex $(BASE); \
	pages2=`sed -n '/inserttotalframenumber/{ s/[^0-9]//g; p; }' < $$AUX`; \
	if [ $$pages1 -ne $$pages2 ]; then pdflatex $(BASE); fi; \
	)
	
clean:
	@rm -f *.aux
	@rm -f *.log
	@rm -f *.nav
	@rm -f *.out
	@rm -f *.snm
	@rm -f *.toc
	@rm -f *.vrb
