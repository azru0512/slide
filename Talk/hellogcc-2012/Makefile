# Generic makefile for processing Beamer files
# 
# Rouben Rostamian <rostamian@umbc.edu>
# December 2004

BASE	= hellogcc-2012-chenwj

FIGURES = \

$(BASE).pdf: $(BASE).tex $(FIGURES)
	@(\
	AUX=$(BASE).aux; \
	if [ ! -f $$AUX ]; then pdflatex $(BASE); fi; \
	pages1=`sed -n '/inserttotalframenumber/{ s/[^0-9]//g; p; }' < $$AUX`; \
	pdflatex $(BASE); \
	pages2=`sed -n '/inserttotalframenumber/{ s/[^0-9]//g; p; }' < $$AUX`; \
	if [ $$pages1 -ne $$pages2 ]; then pdflatex $(BASE); fi; \
	)
	
clean:
	@rm -f $(BASE).{aux,log,nav,out,pdf,snm,toc}
