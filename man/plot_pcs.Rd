% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dimension_reduction.R
\name{plot_pcs}
\alias{plot_pcs}
\title{Plot principle components and make them pretty.}
\usage{
plot_pcs(
  pca_data,
  first = "PC1",
  second = "PC2",
  variances = NULL,
  design = NULL,
  plot_title = TRUE,
  plot_labels = NULL,
  x_label = NULL,
  y_label = NULL,
  plot_size = 5,
  outlines = TRUE,
  plot_alpha = NULL,
  size_column = NULL,
  rug = TRUE,
  max_overlaps = 20,
  cis = c(0.95, 0.9),
  ellipse_type = "t",
  ellipse_geom = "polygon",
  label_size = 4,
  ...
)
}
\arguments{
\item{pca_data}{Dataframe of principle components PC1 .. PCN with any other
arbitrary information.}

\item{first}{Principle component PCx to put on the x axis.}

\item{second}{Principle component PCy to put on the y axis.}

\item{variances}{List of the percent variance explained by each component.}

\item{design}{Experimental design with condition batch factors.}

\item{plot_title}{Title for the plot.}

\item{plot_labels}{Parameter for the labels on the plot.}

\item{x_label}{Label for the x-axis.}

\item{y_label}{Label for the y-axis.}

\item{plot_size}{Size of the dots on the plot}

\item{outlines}{Add a black outline to the plotted shapes?}

\item{plot_alpha}{Add an alpha channel to the dots?}

\item{size_column}{Experimental factor to use for sizing the glyphs}

\item{rug}{Include the rugs on the sides of the plot?}

\item{max_overlaps}{Increase overlapping label tolerance.}

\item{cis}{What (if any) confidence intervals to include.}

\item{ellipse_type}{Choose the kernel for the ellipse.}

\item{ellipse_geom}{Use this ggplot geometry.}

\item{label_size}{The text size of the labels.}

\item{...}{Extra arguments dropped into arglist}
}
\value{
gplot2 PCA plot
}
\description{
All the various dimension reduction methods share some of their end-results
in common. Most notably a table of putative components which may be plotted
against one another so that one may stare at the screen and look for
clustering among the samples/genes/whatever.  This function attempts to make
that process as simple and pretty as possible.
}
\examples{
\dontrun{
 pca_plot = plot_pcs(pca_data, first = "PC2", second = "PC4", design = expt$design)
}
}
\seealso{
[directlabels] [ggplot2] [plot_pca] [pca_information]
}
