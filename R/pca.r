# Time-stamp: <Fri Mar 11 15:13:28 2016 Ashton Trey Belew (abelew@gmail.com)>

#' this a function scabbed from Hector and Kwame's cbcbSEQ
#' It just does fast.svd of a matrix against its rowMeans().
#'
#' @param data A data frame to decompose
#' @return a list containing the s,v,u from fast.svd
#' @seealso \pkg{corpcor} \code{\link[corpcor]{fast.svd}}
#' @examples
#' \dontrun{
#'  svd = makeSVD(data)
#' }
#' @export
makeSVD <- function (data) {
    data <- as.matrix(data)
    s <- corpcor::fast.svd(data - rowMeans(data))
    v <- s$v
    rownames(v) <- colnames(data)
    s <- list(v=v, u=s$u, d=s$d)
    return(s)
}

#' Compute variance of each principal component and how they correlate with batch and cond
#' This was copy/pasted from cbcbSEQ
#' https://github.com/kokrah/cbcbSEQ/blob/master/R/explore.R
#'
#' @param v from makeSVD
#' @param d from makeSVD
#' @param condition factor describing experiment
#' @param batch factor describing batch
#' @return A dataframe containig variance, cum. variance, cond.R-sqrd, batch.R-sqrd
#' @export
pcRes <- function(v, d, condition=NULL, batch=NULL){
  pcVar <- round((d^2)/sum(d^2)*100,2)
  cumPcVar <- cumsum(pcVar)
  calculate_rsquared_condition <- function(data) {
      lm_result <- lm(data ~ condition)
  }
  if(!is.null(condition)){
    cond.R2 <- function(y) round(summary(lm(y ~ condition))$r.squared * 100, 2)
    cond.R2 <- apply(v, 2, cond.R2)
  }
  if(!is.null(batch)){
    batch.R2 <- function(y) round(summary(lm(y~batch))$r.squared*100,2)
    batch.R2 <- apply(v, 2, batch.R2)
  }
  if(is.null(condition) & is.null(batch)){
     res <- data.frame(propVar=pcVar,
                      cumPropVar=cumPcVar)
  }
  if(!is.null(batch) & is.null(condition)){
    res <- data.frame(propVar=pcVar,
                      cumPropVar=cumPcVar,
                      batch.R2=batch.R2)
  }
  if(!is.null(condition) & is.null(batch)){
    res <- data.frame(propVar=pcVar,
                      cumPropVar=cumPcVar,
                      cond.R2=cond.R2)
  }
  if(!is.null(condition) & !is.null(batch)){
    res <- data.frame(propVar=pcVar,
                      cumPropVar=cumPcVar,
                      cond.R2=cond.R2,
                      batch.R2=batch.R2)
  }
  return(res)
}

#'   Make a ggplot PCA plot describing the samples' clustering.
#'
#' @param data  an expt set of samples.
#' @param design   a design matrix and.
#' @param plot_colors   a color scheme.
#' @param plot_title   a title for the plot.
#' @param plot_size   size for the glyphs on the plot.
#' @param plot_labels   add labels?  Also, what type?  FALSE, "default", or "fancy".
#' @param ...  arglist from elipsis!
#' @return a list containing the following:
#'   pca = the result of fast.svd()
#'   plot = ggplot2 pca_plot describing the principle component analysis of the samples.
#'   table = a table of the PCA plot data
#'   res = a table of the PCA res data
#'   variance = a table of the PCA plot variance
#' This makes use of cbcbSEQ and prints the table of variance by component.
#' @seealso \code{\link{makeSVD}}, \code{\link[cbcbSEQ]{pcRes}},
#' \code{\link[directlabels]{geom_dl}} \code{\link{plot_pcs}}
#' @examples
#' \dontrun{
#'  pca_plot = hpgl_pca(expt=expt)
#'  pca_plot
#' }
#' @export
hpgl_pca <- function(data, design=NULL, plot_colors=NULL, plot_labels=NULL,
                     plot_title=NULL, plot_size=5, ...) {
    hpgl_env = environment()
    arglist <- list(...)
    plot_names <- arglist$plot_names
    design <- get0("design")
    plot_colors <- get("plot_colors")
    plot_labels <- get0("plot_labels")
    plot_title <- get0("plot_title")
    plot_size <- get0("plot_size")
    data_class <- class(data)[1]
    names <- NULL
    if (data_class == 'expt') {
        design <- data$definitions
        plot_colors <- data$colors
        plot_names <- data$names
        data <- Biobase::exprs(data$expressionset)
    } else if (data_class == 'ExpressionSet') {
        data <- Biobase::exprs(data)
    } else if (data_class == 'list') {
        data <- data$count_table
        if (is.null(data)) {
            stop("The list provided contains no count_table element.")
        }
    } else if (data_class == 'matrix' | data_class == 'data.frame') {
        data <- as.data.frame(data)  ## some functions prefer matrix, so I am keeping this explicit for the moment
    } else {
        stop("This function currently only understands classes of type: expt, ExpressionSet, data.frame, and matrix.")
    }

    if (is.null(plot_labels)) {
        if (is.null(plot_names)) {
            plot_labels <- colnames(data)
        } else {
            plot_labels <- paste0(colnames(data), ":", plot_names)
        }
    } else if (plot_labels[1] == 'boring') {
        if (is.null(plot_names)) {
            plot_labels <- colnames(data)
        } else {
            plot_labels <- plot_names
        }
    }

    if (is.null(design)) {
        message("No design was provided.  Making one with 1 condition, 1 batch.")
        design <- cbind(plot_labels, 1)
        design <- as.data.frame(design)
        design$condition <- as.numeric(design$labels)
        colnames(design) <- c("name","batch","condition")
    }
    pca <- makeSVD(data)  ## This is a part of cbcbSEQ
    included_batches <- as.factor(as.character(design$batch))
    included_conditions <- as.factor(as.character(design$condition))
    if (length(levels(included_conditions)) == 1 & length(levels(included_batches)) == 1) {
        warning("There is only one condition and one batch, it is impossible to get meaningful pcRes information.")
    } else if (length(levels(included_conditions)) == 1) {
        warning("There is only one condition, but more than one batch.   Going to run pcRes with the batch information.")
        pca_res <- pcRes(v=pca$v, d=pca$d, batch=design$batch)
    } else if (length(levels(included_batches)) == 1) {
        print("There is just one batch in this data.")
        pca_res <- pcRes(v=pca$v, d=pca$d, condition=design$condition)
    } else {
        pca_res <- pcRes(v=pca$v, d=pca$d, condition=design$condition, batch=design$batch)
    }
    pca_variance <- round((pca$d ^ 2) / sum(pca$d ^ 2) * 100, 2)
    xl <- sprintf("PC1: %.2f%% variance", pca_variance[1])
    yl <- sprintf("PC2: %.2f%% variance", pca_variance[2])
    if (is.null(colors)) {
        plot_colors <- as.numeric(as.factor(design$condition))
    }
    pca_data <- data.frame("SampleID" = as.character(design$sample),
                           "condition" = as.character(design$condition),
                           "batch" = as.character(design$batch),
                           "batch_int" = as.integer(as.factor(design$batch)),
                           "PC1" = pca$v[,1],
                           "PC2" = pca$v[,2],
                           "colors" = plot_colors,
                           "labels" = as.character(plot_labels))
    pca_plot <- NULL
    ## I think these smallbatch/largebatch functions are no longer needed
    ## Lets see what happens if I replace this with a single call...
    ##if (num_batches <= 5) {
    ##    pca_plot <- pca_plot_smallbatch(pca_data, size=plot_size, first='PC1', second='PC2')
    ##} else {
    ##    pca_plot <- pca_plot_largebatch(pca_data, size=plot_size, first='PC1', second='PC2')
    ##}
    pca_plot <- plot_pcs(pca_data, size=plot_size, first='PC1', second='PC2', design=design)
    pca_plot <- pca_plot +
        ggplot2::xlab(xl) +
        ggplot2::ylab(yl) +
        ggplot2::theme_bw() +
        ggplot2::theme(legend.key.size=grid::unit(0.5, "cm"))
    if (!is.null(plot_labels)) {
        if (plot_labels[[1]] == "fancy") {
            pca_plot <- pca_plot + directlabels::geom_dl(ggplot2::aes_string(label="SampleID"), method="smart.grid")
        } else if (plot_labels[[1]] == "normal") {
            pca_plot <- pca_plot +
                ggplot2::geom_text(ggplot2::aes_string(x="PC1",
                                                       y="PC2",
                                                       label='paste(design$condition, design$batch, sep="_")'),
                                   angle=45, size=4, vjust=2)
        } else {
            pca_plot <- pca_plot +
                ## remember labels at this point is in the df made on line 96
                ggplot2::geom_text(ggplot2::aes_string(x="PC1", y="PC2", label="labels"),
                                   angle=45, size=4, vjust=2)
        }
    }

    if (!is.null(plot_title)) {
        pca_plot <- pca_plot + ggplot2::ggtitle(plot_title)
    }
    pca_return <- list(
        pca=pca, plot=pca_plot, table=pca_data, res=pca_res, variance=pca_variance)
    return(pca_return)
}

#' Collect the r^2 values from a linear model fitting between a singular
#' value decomposition and factor.
#'
#' @param svd_v  the V' V = I portion of a fast.svd call.
#' @param factor  an experimental factor from the original data.
#' @return The r^2 values of the linear model as a percentage.
#' @seealso \code{\link[corpcor]{fast.svd}}
#' @export
factor_rsquared <- function(svd_v, factor) {
    svd_lm <- try(stats::lm(svd_v ~ factor), silent=TRUE)
    if (class(svd_lm) == 'try-error') {
        result <- 0
    } else {
        lm_summary <- stats::summary.lm(svd_lm)
        r_squared <- lm_summary$r.squared
        result <- round(r_squared * 100, 3)
    }
    return(result)
}

#' A quick and dirty PCA plotter of arbitrary components against one another.
#'
#' @param data  a dataframe of principle components PC1 .. PCN with any other arbitrary information.
#' @param first   principle component PCx to put on the x axis.
#' @param second   principle component PCy to put on the y axis.
#' @param variances   a list of the percent variance explained by each component.
#' @param design   the experimental design with condition batch factors.
#' @param plot_title   a title for the plot.
#' @param plot_labels   a parameter for the labels on the plot.
#' @param size  The size of the dots on the plot
#' @return a ggplot2 PCA plot
#' @seealso \pkg{ggplot2} \code{\link[directlabels]{geom_dl}}
#' @examples
#' \dontrun{
#'  pca_plot = plot_pcs(pca_data, first="PC2", second="PC4", design=expt$design)
#' }
#' @export
plot_pcs <- function(pca_data, first="PC1", second="PC2", variances=NULL,
                     design=NULL, plot_title=NULL, plot_labels=NULL, size=5) {
    hpgl_env <- environment()
    batches <- design$batch
    point_labels <- factor(design$condition)
    if (is.null(plot_title)) {
        plot_title <- paste(first, " vs. ", second, sep="")
    }
    ## colors = levels(as.factor(unlist(design$color)))
    ## num_batches = length(levels(factor(design$batch)))

    ## I really need to switch this to a call to the other plotters (small/largebatch)
    num_batches <- length(unique(batches))
    pca_plot <- NULL
    if (num_batches <= 5) {
        pca_plot <- ggplot2::ggplot(data=as.data.frame(pca_data), ggplot2::aes_string(x="get(first)", y="get(second)"), environment=hpgl_env) +
            ggplot2::geom_point(size=size, ggplot2::aes_string(shape="as.factor(batches)", fill="condition"), colour='black') +
            ggplot2::scale_fill_manual(name="Condition", guide="legend",
                                       labels=levels(as.factor(pca_data$condition)),
                                       values=levels(as.factor(pca_data$colors))) +
            ggplot2::scale_shape_manual(name="Batch", labels=levels(as.factor(pca_data$batch)), values=21:25) +
            ggplot2::guides(fill=ggplot2::guide_legend(override.aes=list(colour=levels(factor(pca_data$colors)))),
                            colour=ggplot2::guide_legend(override.aes="black"))
    } else {
        pca_plot <- ggplot2::ggplot(pca_data, ggplot2::aes_string(x="get(first)", y="get(second)"), environment=hpgl_env) +
            ## geom_point(size=3, aes(shape=factor(df$batch), fill=condition, colour=colors)) +
            ggplot2::geom_point(size=size, ggplot2::aes_string(shape="batch", fill="condition", colour="colors")) +
            ggplot2::scale_fill_manual(name="Condition", guide="legend",
                                       labels=levels(as.factor(pca_data$condition)),
                                       values=levels(as.factor(pca_data$colors))) +
            ggplot2::scale_color_manual(name="Condition", guide="legend",
                                        labels=levels(as.factor(pca_data$condition)),
                                        values=levels(as.factor(pca_data$colors))) +
            ggplot2::guides(fill=ggplot2::guide_legend(override.aes=list(colour=levels(factor(pca_data$colors)))),
                            colour=ggplot2::guide_legend(override.aes="black")) +
            ggplot2::scale_shape_manual(values=c(1:num_batches), name="Batch") +
            ggplot2::theme_bw()
    }

    if (!is.null(variances)) {
        x_var_num <- as.numeric(gsub("PC", "", first))
        y_var_num <- as.numeric(gsub("PC", "", second))
        x_label <- paste("PC", x_var_num, ": ", variances[[x_var_num]], "%  variance", sep="")
        y_label <- paste("PC", y_var_num, ": ", variances[[y_var_num]], "%  variance", sep="")
        pca_plot <- pca_plot + ggplot2::xlab(x_label) + ggplot2::ylab(y_label)
    }

    if (!is.null(plot_labels)) {
        if (plot_labels[[1]] == "fancy") {
            pca_plot <- pca_plot +
                directlabels::geom_dl(ggplot2::aes_string(x="get(first)", y="get(second)", label="point_labels"),
                                      list("top.bumpup", cex=0.5))
        } else {
            pca_plot <- pca_plot +
                ggplot2::geom_text(ggplot2::aes_string(x="get(first)", y="get(second)", label="point_labels"),
                                   angle=45, size=4, vjust=2)
        }
    }
    return(pca_plot)
}

## An alternate to plotting rank order of svd$u
## The plotted_u1s and such below
## y-axis is z(i), x-axis is i
## z(i) = cumulative sum of $u squared
## z = cumsum((svd$u ^ 2))

#' Plot the rank order svd$u elements to get a view of how much
#' the first genes contribute to the total variance by PC.
#'
#' @param plotted_us  a list of svd$u elements
#' @return a recordPlot() plot showing the first 3 PCs by rank-order svd$u.
#' @export
u_plot <- function(plotted_us) {
    plotted_us <- abs(plotted_us[,c(1,2,3)])
    plotted_u1s <- plotted_us[order(plotted_us[,1], decreasing=TRUE),]
    plotted_u2s <- plotted_us[order(plotted_us[,2], decreasing=TRUE),]
    plotted_u3s <- plotted_us[order(plotted_us[,3], decreasing=TRUE),]
    ## allS <- BiocGenerics::rank(allS, ties.method = "random")
    ## plotted_us$rank = rank(plotted_us[,1], ties.method="random")
    plotted_u1s <- cbind(plotted_u1s, rev(rank(plotted_u1s[,1], ties.method="random")))
    plotted_u1s <- plotted_u1s[,c(1,4)]
    colnames(plotted_u1s) <- c("PC1","rank")
    plotted_u1s <- data.frame(plotted_u1s)
    plotted_u1s$ID <- as.character(rownames(plotted_u1s))
    plotted_u2s <- cbind(plotted_u2s, rev(rank(plotted_u2s[,2], ties.method="random")))
    plotted_u2s <- plotted_u2s[,c(2,4)]
    colnames(plotted_u2s) <- c("PC2","rank")
    plotted_u2s <- data.frame(plotted_u2s)
    plotted_u2s$ID <- as.character(rownames(plotted_u2s))
    plotted_u3s <- cbind(plotted_u3s, rev(rank(plotted_u3s[,3], ties.method="random")))
    plotted_u3s <- plotted_u3s[,c(3,4)]
    colnames(plotted_u3s) <- c("PC3","rank")
    plotted_u3s <- data.frame(plotted_u3s)
    plotted_u3s$ID <- as.character(rownames(plotted_u3s))
    plotted_us <- merge(plotted_u1s, plotted_u2s, by.x="rank", by.y="rank")
    plotted_us <- merge(plotted_us, plotted_u3s, by.x="rank", by.y="rank")
    colnames(plotted_us) <- c("rank","PC1","ID1","PC2","ID2","PC3","ID3")
    rm(plotted_u1s)
    rm(plotted_u2s)
    rm(plotted_u3s)
    ## top_threePC = head(plotted_us, n=20)
    plotted_us <- plotted_us[,c("PC1","PC2","PC3")]
    plotted_us$ID <- rownames(plotted_us)
    message("The more shallow the curves in these plots, the more genes responsible for this principle component.")
    plot(plotted_us)
    u_plot <- grDevices::recordPlot()
    return(u_plot)
}

#' Gather information about principle components.
#'
#' Calculate some information useful for generating PCA plots.
#'
#' pca_information seeks to gather together interesting information
#' to make principle component analyses easier, including: the results
#' from (fast.)svd, a table of the r^2 values, a table of the
#' variances in the data, coordinates used to make a pca plot for an
#' arbitrarily large set of PCs, correlations and fstats between
#' experimental factors and the PCs, and heatmaps describing these
#' relationships.  Finally, it will provide a plot showing how much of
#' the variance is provided by the top-n genes and (optionally) the
#' set of all PCA plots with respect to one another. (PCx vs. PCy)
#'
#' @section Warning:
#'  This function has gotten too damn big and needs to be split up.
#'
#' @param expt_data  the data to analyze (usually exprs(somedataset)).
#' @param expt_design   a dataframe describing the experimental design, containing columns with
#'   useful information like the conditions, batches, number of cells, whatever...
#' @param expt_factors   a character list of experimental conditions to query
#'   for R^2 against the fast.svd of the data.
#' @param num_components   a number of principle components to compare the design factors against.
#'   If left null, it will query the same number of components as factors asked for.
#' @param plot_pcas   plot the set of PCA plots for every pair of PCs queried.
#' @param plot_labels   how to label the glyphs on the plot.
#' @return a list of fun pca information:
#'   svd_u/d/v: The u/d/v parameters from fast.svd
#'   rsquared_table: A table of the rsquared values between each factor and principle component
#'   pca_variance: A table of the pca variances
#'   pca_data: Coordinates for a pca plot
#'   pca_cor: A table of the correlations between the factors and principle components
#'   anova_fstats: the sum of the residuals with the factor vs without (manually calculated)
#'   anova_f: The result from performing anova(withfactor, withoutfactor), the F slot
#'   anova_p: The p-value calculated from the anova() call
#'   anova_sums: The RSS value from the above anova() call
#'   cor_heatmap: A heatmap from recordPlot() describing pca_cor.
#' @seealso \code{\link[corpcor]{fast.svd}}, \code{\link[stats]{lm}}
#' @examples
#' \dontrun{
#'  pca_info = pca_information(exprs(some_expt$expressionset), some_design, "all")
#'  pca_info
#' }
#' @export
pca_information <- function(expt_data, expt_design=NULL, expt_factors=c("condition","batch"),
                            num_components=NULL, plot_pcas=FALSE, plot_labels="fancy") {
    ## hpgl_env = environment()
    expt_design <- get0("expt_design")
    expt_factors <- get0("expt_factors")
    num_components <- get0("num_components")
    plot_labels <- get0("plot_labels")
    plot_pcas <- get0("plot_pcas")
    data_class <- class(expt_data)[1]
    if (data_class == 'expt') {
        expt_design <- expt_data$definitions
        expt_data <- Biobase::exprs(expt_data$expressionset)
    } else if (data_class == 'ExpressionSet') {
        expt_data <- Biobase::exprs(expt_data)
    } else if (data_class == 'matrix' | data_class == 'data.frame') {
        expt_data <- as.matrix(expt_data)
    } else {
        stop("This function currently only understands classes of type: expt, ExpressionSet, data.frame, and matrix.")
    }
    expt_data <- as.matrix(expt_data)
    expt_means <- rowMeans(expt_data)
    decomposed <- corpcor::fast.svd(expt_data - expt_means)
    positives <- decomposed$d
    u <- decomposed$u
    v <- decomposed$v
    ## A neat idea from Kwame, rank order plot the U's in the svd version of:
    ## [Covariates] = [U][diagonal][V] for a given PC (usually/always PC1)
    ## The idea being: the resulting decreasing line should be either a slow even
    ## decrease if many genes are contributing to the given component
    ## Conversely, that line should drop suddenly if dominated by one/few genes.
    rownames(u) <- rownames(expt_data)
    rownames(v) <- colnames(expt_data)
    u_plot <- u_plot(u)
    component_variance <- round((positives^2) / sum(positives^2) * 100, 3)
    cumulative_pc_variance <- cumsum(component_variance)
    ## Include in this table the fstatistic and pvalue described in rnaseq_bma.rmd
    component_rsquared_table <- data.frame(
        "prop_var" = component_variance,
        "cumulative_prop_var" = cumulative_pc_variance)
    if (is.null(expt_factors)) {
        expt_factors <- colnames(expt_design)
    } else if (expt_factors[1] == "all") {
        expt_factors <- colnames(expt_design)
    }
    for (component in expt_factors) {
        comp <- factor(as.character(expt_design[, component]), exclude=FALSE)
        column <- apply(v, 2, factor_rsquared, factor=comp)
        component_rsquared_table[component] <- column
    }
    pca_variance <- round((positives ^ 2) / sum(positives ^2) * 100, 2)
    xl <- sprintf("PC1: %.2f%% variance", pca_variance[1])
    print(xl)
    yl <- sprintf("PC2: %.2f%% variance", pca_variance[2])
    print(yl)
    plot_labels <- rownames(expt_design)
    pca_data <- data.frame("SampleID" = plot_labels,
                           "condition" = expt_design$condition,
                           "batch" = expt_design$batch,
                           "batch_int" = as.integer(expt_design$batch),
                           "colors" = as.factor(as.character(expt_design$color)))
    pc_df <- data.frame("SampleID" = plot_labels)
    rownames(pc_df) <- make.names(plot_labels)

    if (is.null(num_components)) {
        num_components <- length(expt_factors)
    }
    for (pc in 1:num_components) {
        name <- paste("PC", pc, sep="")
        pca_data[name] <- v[,pc]
        pc_df[name] <- v[,pc]
    }
    pc_df <- pc_df[-1]
    pca_plots <- list()
    if (isTRUE(plot_pcas)) {
        for (pc in 1:num_components) {
            next_pc <- pc + 1
            name <- paste("PC", pc, sep="")
            for (second_pc in next_pc:num_components) {
                if (pc < second_pc & second_pc <= num_components) {
                    second_name <- paste("PC", second_pc, sep="")
                    list_name <- paste(name, "_", second_name, sep="")
                    ## Sometimes these plots fail because too many grid operations are happening.
                    tmp_plot <- try(print(plot_pcs(pca_data,
                                                   design=expt_design,
                                                   variances=pca_variance,
                                                   first=name,
                                                   second=second_name,
                                                   plot_labels=plot_labels)))
                    pca_plots[[list_name]] <- tmp_plot
                }
            }
        }
    }
    factor_df <- data.frame("SampleID" = plot_labels)
    rownames(factor_df) <- make.names(plot_labels)
    for (fact in expt_factors) {
        factor_df[fact] <- as.numeric(as.factor(as.character(expt_design[, fact])))
    }
    factor_df <- factor_df[-1]
    ## fit_one = data.frame()
    ## fit_two = data.frame()
    cor_df <- data.frame()
    anova_rss <- data.frame()
    anova_sums <- data.frame()
    anova_f <- data.frame()
    anova_p <- data.frame()
    anova_rss <- data.frame()
    anova_fstats <- data.frame()
    for (fact in expt_factors) {
        for (pc in 1:num_components) {
            factor_name <- names(factor_df[fact])
            pc_name <- names(pc_df[pc])
            tmp_df <- merge(factor_df, pc_df, by="row.names")
            rownames(tmp_df) <- tmp_df[,1]
            tmp_df <- tmp_df[-1]
            lmwithfactor_test <- try(stats::lm(formula=get(pc_name) ~ 1 + get(factor_name), data=tmp_df))
            lmwithoutfactor_test <- try(stats::lm(formula=get(pc_name) ~ 1, data=tmp_df))
            ## This fstat provides a metric of how much variance is removed by including this specific factor
            ## in the model vs not.  Therefore higher numbers tell us that adding that factor
            ## removed more variance and are more important.
            fstat <- sum(residuals(lmwithfactor_test)^2) / sum(residuals(lmwithoutfactor_test)^2)
            ##1.  Perform lm(pc ~ 1 + factor) which is fit1
            ##2.  Perform lm(pc ~ 1) which is fit2
            ##3.  The Fstat is then defined as (sum(residuals(fit1)^2) / sum(residuals(fit2)^2))
            ##4.  The resulting p-value is 1 - pf(Fstat, (n-(#levels in the factor)), (n-1))  ## n is the number of samples in the fit
            ##5.  Look at anova.test() to see if this provides similar/identical information
            another_fstat <- try(stats::anova(lmwithfactor_test, lmwithoutfactor_test), silent=TRUE)
            if (class(another_fstat)[1] == 'try-error') {
                anova_sums[fact, pc] <- 0
                anova_f[fact, pc] <- 0
                anova_p[fact, pc] <- 0
                anova_rss[fact, pc] <- 0
            } else {
                anova_sums[fact, pc] <- another_fstat$S[2]
                anova_f[fact, pc] <- another_fstat$F[2]
                anova_p[fact, pc] <- another_fstat$P[2]
                anova_rss[fact, pc] <- another_fstat$RSS[1]
            }
            anova_fstats[fact, pc] <- fstat
            cor_test <- NULL
            tryCatch(
                {
                    cor_test <- cor.test(tmp_df[, factor_name], tmp_df[, pc_name], na.rm=TRUE)
                },
                error=function(cond) {
                    message(paste("The correlation failed for ", factor_name, " and ", pc_name, ".", sep=""))
                    cor_test <- 0
                },
                warning=function(cond) {
                    message(paste("The standard deviation was 0 for ", factor_name, " and ", pc_name, ".", sep=""))
                },
                finally={
                }
            ) ## End of the tryCatch
            if (class(cor_test) == 'try-error' | is.null(cor_test)) {
                cor_df[fact, pc] <- 0
            } else {
                cor_df[fact, pc] <- cor_test$estimate
            }
        }
    }
    rownames(cor_df) <- colnames(factor_df)
    colnames(cor_df) <- colnames(pc_df)
    colnames(anova_sums) <- colnames(pc_df)
    colnames(anova_f) <- colnames(pc_df)
    colnames(anova_p) <- colnames(pc_df)
    colnames(anova_rss) <- colnames(pc_df)
    colnames(anova_fstats) <- colnames(pc_df)
    cor_df <- as.matrix(cor_df)
    ## silly_colors = grDevices::colorRampPalette(brewer.pal(9, "Purples"))(100)
    silly_colors <- grDevices::colorRampPalette(c("purple","black","yellow"))(100)
    cor_df <- cor_df[complete.cases(cor_df),]
    pc_factor_corheat <- heatmap.3(cor_df, scale="none", trace="none", linewidth=0.5,
                                   keysize=2, margins=c(8,8), col=silly_colors,
                                   dendrogram="none", Rowv=FALSE, Colv=FALSE,
                                   main="cor(factor, PC)")
    pc_factor_corheat <- grDevices::recordPlot()
    anova_f_colors <- grDevices::colorRampPalette(c("blue","black","red"))(100)
    anova_f_heat <- heatmap.3(as.matrix(anova_f), scale="none", trace="none",
                              linewidth=0.5, keysize=2, margins=c(8,8), col=anova_f_colors,
                              dendrogram = "none", Rowv=FALSE, Colv=FALSE,
                              main="anova fstats for (factor, PC)")
    anova_f_heat <- grDevices::recordPlot()
    anova_fstat_colors <- grDevices::colorRampPalette(c("blue","white","red"))(100)
    anova_fstat_heat <- heatmap.3(as.matrix(anova_fstats), scale="none", trace="none", linewidth=0.5,
                                  keysize=2, margins=c(8,8), col=anova_fstat_colors, dendrogram="none",
                                  Rowv=FALSE, Colv=FALSE, main="anova fstats for (factor, PC)")
    anova_fstat_heat <- grDevices::recordPlot()
    neglog_p <- -1 * log(as.matrix(anova_p) + 1)
    anova_neglogp_colors <- grDevices::colorRampPalette(c("blue","white","red"))(100)
    anova_neglogp_heat <- heatmap.3(as.matrix(neglog_p), scale="none", trace="none", linewidth=0.5,
                                    keysize=2, margins=c(8,8), col=anova_f_colors, dendrogram="none",
                                    Rowv=FALSE, Colv=FALSE, main="-log(anova_p values)")
    anova_neglogp_heat <- grDevices::recordPlot()
    ## Another option: -log10 p-value of the ftest for this heatmap.
    ## covariate vs PC score
    ## Analagously: boxplot(PCn ~ batch)
    pca_list <- list(
        pc1_trend=u_plot,svd_d=positives, svd_u=u, svd_v=v, rsquared_table=component_rsquared_table,
        pca_variance=pca_variance, pca_data=pca_data, anova_fstats=anova_fstats, anova_sums=anova_sums,
        anova_f=anova_f, anova_p=anova_p, pca_cor=cor_df, cor_heatmap=pc_factor_corheat,
        anova_f_heatmap=anova_f_heat, anova_fstat_heatmap=anova_fstat_heat,
        anova_neglogp_heatmaph=anova_neglogp_heat, pca_plots=pca_plots
    )
    return(pca_list)
}

#' Get the highest/lowest scoring genes for every principle component.
#'
#' This function uses princomp to acquire a principle component biplot
#' for some data and extracts a dataframe of the top n genes for each
#' component by score.
#'
#' @param df   a dataframe of (pseudo)counts
#' @param conditions   a factor or character of conditions in the experiment.
#' @param batches   a factor or character of batches in the experiment.
#' @param n   the number of genes to extract.
#' @return a list including the princomp biplot, histogram, and tables
#' of top/bottom n scored genes with their scores by component.
#' @seealso \code{\link[stats]{princomp}}
#' @examples
#' \dontrun{
#'  information = pca_highscores(df=df, conditions=cond, batches=bat)
#'  information$pca_bitplot  ## oo pretty
#' }
#' @export
pca_highscores <- function(df=NULL, conditions=NULL, batches=NULL, n=20) {
    ## Another method of using PCA
    ## cond = as.factor(as.numeric(conditions))
    ## batch = as.factor(as.numeric(batches))
    another_pca <- try(stats::princomp(x=df, cor=TRUE, scores=TRUE, formula=~0 + cond + batch))
    plot(another_pca)
    pca_hist <- grDevices::recordPlot()
    biplot(another_pca)
    pca_biplot <- grDevices::recordPlot()
    highest <- NULL
    lowest <- NULL
    for (pc in 1:length(colnames(another_pca$scores))) {
        tmphigh <- another_pca$scores
        tmplow <- another_pca$scores
        tmphigh <- tmphigh[order(tmphigh[,pc], decreasing=TRUE),]
        tmphigh <- head(tmphigh, n=20)
        tmplow <- tmplow[order(tmplow[,pc], decreasing=FALSE),]
        tmplow <- head(tmplow, n=20)
        high_column <- paste0(signif(tmphigh[,pc], 4), ":", rownames(tmphigh))
        low_column <- paste0(signif(tmplow[,pc], 4), ":", rownames(tmplow))
        highest <- cbind(highest, high_column)
        lowest <- cbind(lowest, low_column)
    }
    colnames(highest) <- colnames(another_pca$scores)
    colnames(lowest) <- colnames(another_pca$scores)
    ret_list <- list(
        pca_hist=pca_hist,
        pca_biplot=pca_biplot,
        highest=highest,
        lowest=lowest)
    return(ret_list)
}

## EOF