## Going to try and recapitulate the analyses found at:
## https://github.com/jtleek/svaseq/blob/master/recount.Rmd
## and use the results to attempt to more completely understand surrogates in our data

#' Extract some surrogate estimations from a raw data set using sva, ruv, and/or pca.
#'
#' This applies the methodologies very nicely explained by Jeff Leek at
#' https://github.com/jtleek/svaseq/blob/master/recount.Rmd
#' and attempts to use them to acquire estimates which may be applied to an experimental model
#' by either EdgeR, DESeq2, or limma.  In addition, it modifies the count tables using these
#' estimates so that one may play with the modified counts and view the changes (with PCA or heatmaps
#' or whatever).  Finally, it prints a couple of the plots shown by Leek in his document.
#' In other words, this is entirely derivative of someone much smarter than me.
#'
#' @param input  Expt or data frame to manipulate.
#' @param design  If the data is not an expt, provide experimental design here.
#' @param estimate_type  One of: sva_supervised, sva_unsupervised, ruv_empirical, ruv_supervised,
#'  ruv_residuals, or pca.
#' @param surrogates  Choose a method for getting the number of surrogates, be or leek, or a number.
#' @param expt_state  Current state of the expt object (to check for log2, cpm, etc)
#' @param ... Parameters fed to arglist.
#' @return List including the adjustments for a model matrix, a modified count table, and 3 plots of
#'  the known batch, surrogates, and batch/surrogate.
#' @seealso \pkg{Biobase} \pkg{sva} \pkg{EDASeq} \pkg{RUVseq} \pkg{edgeR}
#' @export
get_model_adjust <- function(input, design=NULL, estimate_type="sva",
                             surrogates="be", expt_state=NULL, confounders=NULL, ...) {
  arglist <- list(...)
  my_design <- NULL
  my_data <- NULL
  transform_state <- "raw"
  log_data <- NULL
  log2_mtrx <- NULL
  base10_data <- NULL
  base10_mtrx <- NULL
  ## Gather all the likely pieces we can use
  ## Without the following requireNamespace(ruv)
  ## we get an error 'unable to find an inherited method for function RUVr'
  ruv_loaded <- try(require(package="ruv", quietly=TRUE))
  ## In one test, this seems to have been enough, but in another, perhaps not.

  filter <- "raw"
  if (!is.null(arglist[["filter"]])) {
    filter <- arglist[["filter"]]
  }
  convert <- "cpm"
  if (!is.null(arglist[["convert"]])) {
    convert <- arglist[["convert"]]
  }
  if (class(input) == "expt") {
    ## Gather all the likely pieces we can use
    my_design <- input[["design"]]
    my_data <- as.data.frame(exprs(input))
    transform_state <- input[["state"]][["transform"]]
    base10_mtrx <- as.matrix(my_data)
    log_mtrx <- as.matrix(my_data)
    if (transform_state == "raw") {
      ## I think this was the cause of some problems.  The order of operations performed here
      ## was imperfect and could potentially lead to multiple different matrix sizes.
      base10_data <- sm(normalize_expt(input, convert=convert, filter=filter, thresh=1))
      base10_mtrx <- exprs(base10_data)
      log_data <- sm(normalize_expt(base10_data, transform="log2"))
      log2_mtrx <- exprs(log_data)
      rm(log_data)
      rm(base10_data)
    } else {
      log2_mtrx <- as.matrix(my_data)
      base10_mtrx <- as.matrix(2 ^ my_data) - 1
    }
  } else {
    if (is.null(design)) {
      stop("If an expt is not passed, then design _must_ be.")
    }
    message("Not able to discern the state of the data.")
    message("Going to use a simplistic metric to guess if it is log scale.")
    my_design <- design
    if (max(input) > 100) {
      transform_state <- "raw"
    } else {
      transform_state <- "log2"
    }
    my_data <- input
    base10_mtrx <- as.matrix(my_data)
    log_mtrx <- as.matrix(my_data)
    if (transform_state == "raw") {
      log_data <- sm(hpgl_norm(input, convert="cpm", transform="log2", filter=filter, thresh=1))
      log2_mtrx <- as.matrix(log_data[["count_table"]])
      ## base10_data <- sm(hpgl_norm(data, convert="cpm", filter=filter, thresh=1))
      ## base10_mtrx <- as.matrix(base10_data[["count_table"]])
      base10_mtrx <- (2 ^ log2_mtrx) - 1
      rm(log_data)
      ## rm(base10_data)
    } else {
      log2_mtrx <- as.matrix(input)
      base10_mtrx <- as.matrix(2 ^ input) - 1
    }
  }

  conditions <- droplevels(as.factor(my_design[["condition"]]))
  batches <- droplevels(as.factor(my_design[["batch"]]))
  conditional_model <- model.matrix(~ conditions, data=my_design)
  sample_names <- colnames(input)
  null_model <- conditional_model[, 1]
  chosen_surrogates <- 1
  if (is.null(surrogates)) {
    message("No estimate nor method to find surrogates was provided. Assuming you want 1 surrogate variable.")
  } else {
    if (class(surrogates) == "character") {
      ## num.sv assumes the log scale.
      if (surrogates == "smartsva") {
        lm_rslt <- lm(t(base10_mtrx) ~ condition, data=my_design)
        sv_estimate_data <- t(resid(lm_rslt))
        chosen_surrogates <- isva::EstDimRMT(sv_estimate_data, FALSE)[["dim"]] + 1
      } else if (surrogates == "isva") {
        chosen_surrogates <- isva::EstDimRMT(log2_mtrx)
      } else if (surrogates != "be" & surrogates != "leek") {
        message("A string was provided, but it was neither 'be' nor 'leek', assuming 'be'.")
        chosen_surrogates <- sm(sva::num.sv(dat=log2_mtrx, mod=conditional_model))
      } else {
        chosen_surrogates <- sm(sva::num.sv(dat=log2_mtrx,
                                            mod=conditional_model, method=surrogates))
      }
      message("The ", surrogates, " method chose ",
              chosen_surrogates, " surrogate variable(s).")
    } else if (class(surrogates) == "numeric") {
      message("A specific number of surrogate variables was chosen: ", surrogates, ".")
      chosen_surrogates <- surrogates
    }
  }
  if (chosen_surrogates < 1) {
    message("One must have greater than 0 surrogates, setting chosen_surrogates to 1.")
    chosen_surrogates <- 1
  }

  ## empirical controls can take either log or base 10 scale depending on 'control_type'
  control_type <- "norm"
  control_likelihoods <- NULL
  if (control_type == "norm") {
    control_likelihoods <- try(sm(sva::empirical.controls(dat=log2_mtrx,
                                                          mod=conditional_model,
                                                          mod0=null_model,
                                                          n.sv=chosen_surrogates,
                                                          type=control_type)))
  } else {
    control_likelihoods <- try(sm(sva::empirical.controls(dat=base10_mtrx,
                                                          mod=conditional_model,
                                                          mod0=null_model,
                                                          n.sv=chosen_surrogates,
                                                          type=control_type)))
  }
  if (class(control_likelihoods) == "try-error") {
    message("The most likely error in sva::empirical.controls() is a call to density in irwsva.build.
Setting control_likelihoods to zero and using unsupervised sva.")
    warning("It is highly likely that the underlying reason for this error is too many 0's in
the dataset, please try doing a filtering of the data and retry.")
    control_likelihoods <- 0
  }
  if (sum(control_likelihoods) == 0) {
    if (estimate_type == "sva_supervised") {
      message("Unable to perform supervised estimations, changing to unsupervised_sva.")
      estimate_type <- "sva_unsupervised"
    } else if (estimate_type == "ruv_supervised") {
      message("Unable to perform supervised estimations, changing to empirical_ruv.")
      estimate_type <- "ruv_empirical"
    }
  }

  ## I use 'sva' as shorthand fairly often
  if (estimate_type == "sva") {
    estimate_type <- "sva_unsupervised"
    message("Estimate type 'sva' is shorthand for 'sva_unsupervised'.")
    message("Other sva options include: sva_supervised and svaseq.")
  }
  if (estimate_type == "ruv") {
    estimate_type <- "ruv_empirical"
    message("Estimate type 'ruv' is shorthand for 'ruv_empirical'.")
    message("Other ruv options include: ruv_residual and ruv_supervised.")
  }

  surrogate_result <- NULL
  model_adjust <- NULL
  adjusted_counts <- NULL
  type_color <- NULL
  returned_counts <- NULL

  switchret <- switch(
    estimate_type,
    "sva_supervised" = {
      message("Attempting sva supervised surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "red"
      supervised_sva <- sm(sva::ssva(log2_mtrx,
                                     controls=control_likelihoods,
                                     n.sv=chosen_surrogates))
      model_adjust <- as.matrix(supervised_sva[["sv"]])
      surrogate_result <- supervised_sva
    },
    "fsva" = {
      ## Ok, I have a question:
      ## If we perform fsva using log2(data) and get back SVs on a scale of ~ -1
      ## to 1, then why are these valid for changing and visualizing the base10
      ## data.  That does not really make sense to me.
      message("Attempting fsva surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "darkred"
      sva_object <- sm(sva::sva(log2_mtrx, conditional_model,
                                null_model, n.sv=chosen_surrogates))
      fsva_result <- sva::fsva(log2_mtrx, conditional_model,
                               sva_object, newdat=as.matrix(log2_mtrx),
                               method="exact")
      model_adjust <- as.matrix(fsva_result[["newsv"]])
      surrogate_result <- fsva_result
    },
    "isva" = {
      message("Attempting isva surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "darkgreen"
      condition_vector <- as.numeric(conditions)

      confounder_lst <- list()
      if (is.null(confounders)) {
        confounder_lst[["batch"]] <- as.numeric(batches)
      } else {
        for (c in 1:length(confounders)) {
          name <- confounders[c]
          confounder_lst[[name]] <- as.numeric(my_design[[name]])
        }
      }

      confounder_mtrx <- matrix(data=confounder_lst[[1]], ncol=1)
      colnames(confounder_mtrx) <- names(confounder_lst)[1]
      if (length(confounder_lst) > 1) {
        for (i in 2:length(confounder_lst)) {
          confounder_mtrx <- cbind(confounder_mtrx, confounder_lst[[i]])
          names(confounder_mtrx)[i] <- names(confounder_lst)[i]
        }
      }

      ##surrogate_estimate <- EstDimRMT(data.m);
      message("Estmated number of significant components: ", chosen_surrogates, ".")
      ## this makes sense since 1 component is associated with the
      ## the phenotype of interest, while the other two are associated
      ## with the confounders
      ##ncp <- surrogate_estimate[["dim"]] - 1
      ## Do ISVA
      ## run with the confounders as given
      surrogate_result <- isva::DoISVA(
                                  log2_mtrx, condition_vector,
                                  cf.m=NULL, factor.log=FALSE,
                                  ncomp=chosen_surrogates, pvthCF=0.01,
                                  th=0.05, icamethod="JADE")
      model_adjust <- as.matrix(surrogate_result[["isv"]])
      ## I think this is not what one should use in a model as the range seems to be
      ## from 1-n where n is quite large.

      ##summary(isva.o)

      ##data(simdataISVA);
      ##data.m <- simdataISVA$data;
      ##pheno.v <- simdataISVA$pheno;
      ## factors matrix (two potential confounding factors, e.g chip and cohort)
      ##factors.m <- cbind(simdataISVA$factors[[1]],simdataISVA$factors[[2]]);
      ##colnames(factors.m) <- c("CF1","CF2");
      ## Estimate number of significant components of variation
      ##rmt.o <- EstDimRMT(data.m);
      ##print(paste("Number of significant components=",rmt.o$dim,sep=""));
      ## this makes sense since 1 component is associated with the
      ## the phenotype of interest, while the other two are associated
      ## with the confounders
      ##ncp <- rmt.o$dim-1 ;
      ## Do ISVA
      ## run with the confounders as given
      ##isva.o <- DoISVA(data.m,pheno.v,factors.m,factor.log=rep(FALSE,2),
      ##                 pvthCF=0.01,th=0.05,ncomp=ncp,icamethod="fastICA");

      ## Evaluation (ISVs should correlate with confounders)
      ## modeling of CFs
      ##print(cor(isva.o$isv,factors.m));
    },
    "smartsva" = {
      message("Attempting svaseq estimation with ",
              chosen_surrogates, " surrogates.")
      surrogate_result <- SmartSVA::smartsva.cpp(
                                      base10_mtrx,
                                      conditional_model,
                                      null_model,
                                      n.sv=chosen_surrogates)
      model_adjust <- as.matrix(surrogate_result[["sv"]])
    },
    "svaseq" = {
      message("Attempting svaseq estimation with ",
              chosen_surrogates, " surrogates.")
      svaseq_result <- sm(sva::svaseq(base10_mtrx,
                                      n.sv=chosen_surrogates,
                                      conditional_model,
                                      null_model))
      surrogate_result <- svaseq_result
      model_adjust <- as.matrix(svaseq_result[["sv"]])
    },
    "sva_unsupervised" = {
      message("Attempting sva unsupervised surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "blue"
      if (min(rowSums(base10_mtrx)) == 0) {
        warning("sva will likely fail because some rowSums are 0.")
      }
      unsupervised_sva_batch <- sm(sva::sva(log2_mtrx,
                                            conditional_model,
                                            null_model,
                                            n.sv=chosen_surrogates))
      surrogate_result <- unsupervised_sva_batch
      model_adjust <- as.matrix(unsupervised_sva_batch[["sv"]])
    },
    "pca" = {
      message("Attempting pca surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "green"
      data_vs_means <- as.matrix(log2_mtrx - rowMeans(log2_mtrx))
      svd_result <- corpcor::fast.svd(data_vs_means)
      surrogate_result <- svd_result
      model_adjust <- as.matrix(svd_result[["v"]][, 1:chosen_surrogates])
    },
    "ruv_supervised" = {
      message("Attempting ruvseq supervised surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "black"
      ## Re-calculating the numer of surrogates with this modified data.
      surrogate_estimate <- sm(sva::num.sv(dat=log2_mtrx, mod=conditional_model))
      if (min(rowSums(base10_mtrx)) == 0) {
        warning("empirical.controls will likely fail because some rows are all 0.")
      }
      control_likelihoods <- sm(sva::empirical.controls(
                                       dat=log2_mtrx,
                                       mod=conditional_model,
                                       mod0=null_model,
                                       n.sv=surrogate_estimate))
      ruv_result <- RUVSeq::RUVg(round(base10_mtrx),
                                 k=surrogate_estimate,
                                 cIdx=as.logical(control_likelihoods))
      surrogate_result <- ruv_result
      returned_counts <- ruv_result[["normalizedCounts"]]
      model_adjust <- as.matrix(ruv_result[["W"]])
    },
    "ruv_residuals" = {
      message("Attempting ruvseq residual surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "purple"
      ## Use RUVSeq and residuals
      ruv_input <- edgeR::DGEList(counts=base10_mtrx, group=conditions)
      norm <- edgeR::calcNormFactors(ruv_input)
      ruv_input <- try(edgeR::estimateDisp(norm, design=conditional_model, robust=TRUE))
      ruv_fit <- edgeR::glmFit(ruv_input, conditional_model)
      ruv_res <- residuals(ruv_fit, type="deviance")
      ruv_normalized <- EDASeq::betweenLaneNormalization(base10_mtrx, which="upper")
      ## This also gets mad if you pass it a df and not matrix
      controls <- rep(TRUE, dim(base10_mtrx)[1])
      ruv_result <- RUVSeq::RUVr(ruv_normalized, controls, k=chosen_surrogates, ruv_res)
      model_adjust <- as.matrix(ruv_result[["W"]])
    },
    "ruv_empirical" = {
      message("Attempting ruvseq empirical surrogate estimation with ",
              chosen_surrogates, " surrogates.")
      type_color <- "orange"
      ruv_input <- edgeR::DGEList(counts=base10_mtrx, group=conditions)
      ruv_input_norm <- edgeR::calcNormFactors(ruv_input, method="upperquartile")
      ruv_input_glm <- edgeR::estimateGLMCommonDisp(ruv_input_norm, conditional_model)
      ruv_input_tag <- edgeR::estimateGLMTagwiseDisp(ruv_input_glm, conditional_model)
      ruv_fit <- edgeR::glmFit(ruv_input_tag, conditional_model)
      ## Use RUVSeq with empirical controls
      ## The previous instance of ruv_input should work here, and the ruv_input_norm
      ## Ditto for _glm and _tag, and indeed ruv_fit
      ## Thus repeat the first 7 lines of the previous RUVSeq before anything changes.
      ruv_lrt <- edgeR::glmLRT(ruv_fit, coef=2)
      ruv_control_table <- ruv_lrt[["table"]]
      ranked <- as.numeric(rank(ruv_control_table[["LR"]]))
      bottom_third <- (summary(ranked)[[2]] + summary(ranked)[[3]]) / 2
      ruv_controls <- ranked <= bottom_third  ## what is going on here?!
      ## ruv_controls = rank(ruv_control_table$LR) <= 400  ## some data sets fail with 400 hard-set
      ruv_result <- RUVSeq::RUVg(round(base10_mtrx), ruv_controls, k=chosen_surrogates)
      surrogate_result <- ruv_result
      model_adjust <- as.matrix(ruv_result[["W"]])
    },
    {
      type_color <- "grey"
      ## If given nothing to work with, use supervised sva
      message("Did not understand ", estimate_type, ", assuming supervised sva.")
      supervised_sva <- sva::svaseq(base10_mtrx,
                                    conditional_model,
                                    null_model,
                                    controls=control_likelihoods,
                                    n.sv=chosen_surrogates)
      model_adjust <- as.matrix(supervised_sva[["sv"]])
      surrogate_result <- supervised_sva
    }
  ) ## End of the switch.

  rownames(model_adjust) <- sample_names
  sv_names <- paste0("SV", 1:ncol(model_adjust))
  colnames(model_adjust) <- sv_names
  new_counts <- counts_from_surrogates(base10_mtrx, model_adjust, design=my_design)
  plotbatch <- as.integer(batches)
  plotcond <- as.numeric(conditions)
  x_marks <- 1:length(colnames(data))

  surrogate_plots <- NULL
  if (class(input) == "expt") {
    surrogate_plots <- plot_batchsv(input, model_adjust)
  }

  ret <- list(
    "surrogate_result" = surrogate_result,
    "null_model" = null_model,
    "model_adjust" = model_adjust,
    "new_counts" = new_counts,
    "sample_factor" = surrogate_plots[["sample_factor"]],
    "factor_svs" = surrogate_plots[["factor_svs"]],
    "svs_sample" = surrogate_plots[["svs_sample"]])
  return(ret)
}

#' Perform a comparison of the surrogate estimators demonstrated by Jeff Leek.
#'
#' This is entirely derivative, but seeks to provide similar estimates for one's
#' own actual data and catch corner cases not taken into account in that
#' document (for example if the estimators don't converge on a surrogate
#' variable). This will attempt each of the surrogate estimators described by
#' Leek: pca, sva supervised, sva unsupervised, ruv supervised, ruv residuals,
#' ruv empirical. Upon completion it will perform the same limma expression
#' analysis and plot the ranked t statistics as well as a correlation plot
#' making use of the extracted estimators against condition/batch/whatever
#' else. Finally, it does the same ranking plot against a linear fitting Leek
#' performed and returns the whole pile of information as a list.
#'
#' @param expt Experiment containing a design and other information.
#' @param extra_factors Character list of extra factors which may be included in the final plot of
#'  the data.
#' @param filter_it  Most of the time these surrogate methods get mad if there
#'   are 0s in the data.  Filter it?
#' @param filter_type  Type of filter to use when filtering the input data.
#' @param do_catplots Include the catplots?  They don't make a lot of sense yet, so probably no.
#' @param surrogates  Use 'be' or 'leek' surrogate estimates, or choose a
#'   number.
#' @param ...  Extra arguments when filtering.
#' @return List of the results.
#' @seealso \code{\link{get_model_adjust}}
#' @export
compare_surrogate_estimates <- function(expt, extra_factors=NULL, filter_it=TRUE, filter_type=TRUE,
                                        do_catplots=FALSE, surrogates="be", ...) {
  arglist <- list(...)
  design <- pData(expt)
  do_batch <- TRUE
  if (length(levels(design[["batch"]])) == 1) {
    message("There is 1 batch in the data, fitting condition+batch will fail.")
    do_batch <- FALSE
  }

  if (isTRUE(filter_it) & expt[["state"]][["filter"]] == "raw") {
    message("The expt has not been filtered, set filter_type/filter_it if you want other options.")
    expt <- sm(normalize_expt(expt, filter=filter_type,
                              ...))
  }
  pca_plots <- list()
  pca_plots[["null"]] <- plot_pca(expt)[["plot"]]

  pca_adjust <- get_model_adjust(expt, estimate_type="pca", surrogates=surrogates)
  pca_plots[["pca"]] <- plot_pca(pca_adjust[["new_counts"]],
                                 design=design,
                                 plot_colors=expt[["colors"]])[["plot"]]

  sva_supervised <- get_model_adjust(expt, estimate_type="sva_supervised", surrogates=surrogates)
  pca_plots[["svasup"]] <- plot_pca(sva_supervised[["new_counts"]],
                                    design=design,
                                    plot_colors=expt[["colors"]])[["plot"]]

  sva_unsupervised <- get_model_adjust(expt, estimate_type="sva_unsupervised", surrogates=surrogates)
  pca_plots[["svaunsup"]] <- plot_pca(sva_unsupervised[["new_counts"]],
                                      design=design,
                                      plot_colors=expt[["colors"]])[["plot"]]

  ruv_supervised <- get_model_adjust(expt, estimate_type="ruv_supervised", surrogates=surrogates)
  pca_plots[["ruvsup"]] <- plot_pca(ruv_supervised[["new_counts"]],
                                    design=design,
                                    plot_colors=expt[["colors"]])[["plot"]]

  ruv_residuals <- get_model_adjust(expt, estimate_type="ruv_residuals", surrogates=surrogates)
  pca_plots[["ruvresid"]] <- plot_pca(ruv_residuals[["new_counts"]],
                                      design=design,
                                      plot_colors=expt[["colors"]])[["plot"]]

  ruv_empirical <- get_model_adjust(expt, estimate_type="ruv_empirical", surrogates=surrogates)
  pca_plots[["ruvemp"]] <- plot_pca(ruv_empirical[["new_counts"]],
                                    design=design,
                                    plot_colors=expt[["colors"]])[["plot"]]

  first_svs <- data.frame(
    "condition" = as.numeric(as.factor(expt[["conditions"]])),
    "batch" = as.numeric(as.factor(expt[["batches"]])),
    "pca_adjust" = pca_adjust[["model_adjust"]][, 1],
    "sva_supervised" = sva_supervised[["model_adjust"]][, 1],
    "sva_unsupervised" = sva_unsupervised[["model_adjust"]][, 1],
    "ruv_supervised" = ruv_supervised[["model_adjust"]][, 1],
    "ruv_residuals" = ruv_residuals[["model_adjust"]][, 1],
    "ruv_empirical" = ruv_empirical[["model_adjust"]][, 1])
  batch_adjustments <- list(
    "condition" = as.factor(expt[["conditions"]]),
    "batch" = as.factor(expt[["batches"]]),
    "pca_adjust" = pca_adjust[["model_adjust"]],
    "sva_supervised" = sva_supervised[["model_adjust"]],
    "sva_unsupervised" = sva_unsupervised[["model_adjust"]],
    "ruv_supervised" = ruv_supervised[["model_adjust"]],
    "ruv_residuals" = ruv_residuals[["model_adjust"]],
    "ruv_empirical" = ruv_empirical[["model_adjust"]])
  batch_names <- c("condition", "batch", "pca", "sva_sup", "sva_unsup",
                   "ruv_sup", "ruv_resid", "ruv_emp")

  if (!is.null(extra_factors)) {
    for (fact in extra_factors) {
      if (!is.null(design[, fact])) {
        batch_names <- append(x=batch_names, values=fact)
        first_svs[[fact]] <- as.numeric(as.factor(design[, fact]))
        batch_adjustments[[fact]] <- as.numeric(as.factor(design[, fact]))
      }
    }
  }
  correlations <- cor(first_svs)
  corrplot::corrplot(correlations, method="ellipse", type="lower", tl.pos="d")
  ret_plot <- grDevices::recordPlot()

  adjustments <- c("+ batch_adjustments$batch", "+ batch_adjustments$pca",
                   "+ batch_adjustments$sva_sup", "+ batch_adjustments$sva_unsup",
                   "+ batch_adjustments$ruv_sup", "+ batch_adjustments$ruv_resid",
                   "+ batch_adjustments$ruv_emp")
  adjust_names <- gsub(pattern="^.*adjustments\\$(.*)$", replacement="\\1", x=adjustments)
  starter <- edgeR::DGEList(counts=exprs(expt))
  norm_start <- edgeR::calcNormFactors(starter)


  ## Create a baseline to compare against.
  null_formula <- as.formula("~ condition ")
  null_limma_design <- model.matrix(null_formula, data=design)
  null_voom_result <- limma::voom(norm_start, null_limma_design, plot=FALSE)
  null_limma_fit <- limma::lmFit(null_voom_result, null_limma_design)
  null_fit <- limma::eBayes(null_limma_fit)
  null_tstat <- null_fit[["t"]]
  null_catplot <- NULL
  if (isTRUE(do_catplots)) {
    if (!isTRUE("ffpe" %in% .packages(all.available=TRUE))) {
      ## ffpe has some requirements which do not install all the time.
      tt <- please_install("ffpe")
    }
    if (isTRUE("ffpe" %in% .packages(all.available=TRUE))) {
      null_catplot <- ffpe::CATplot(-rank(null_tstat), -rank(null_tstat),
                                    maxrank=1000, make.plot=TRUE)
    } else {
      catplots[[adjust_name]] <- NULL
    }
  }

  catplots <- vector("list", length(adjustments))  ## add 1 for a null adjustment
  names(catplots) <- adjust_names
  tstats <- list()
  oldpar <- par(mar=c(5, 5, 5, 5))
  num_adjust <- length(adjust_names)
  ## Now perform other adjustments
  for (a in 1:num_adjust) {
    adjust_name <- adjust_names[a]
    adjust <- adjustments[a]
    if (adjust_name == "batch" & !isTRUE(do_batch)) {
      message("A friendly reminder that there is only 1 batch in the data.")
      tstats[[adjust_name]] <- null_tstat
      catplots[[adjust_name]] <- null_catplot
    } else {
      message(a, "/", num_adjust, ": Performing lmFit(data) etc. with ",
              adjust_name, " in the model.")
      modified_formula <- as.formula(paste0("~ condition ", adjust))
      limma_design <- model.matrix(modified_formula, data=design)
      voom_result <- limma::voom(norm_start, limma_design, plot=FALSE)
      limma_fit <- limma::lmFit(voom_result, limma_design)
      modified_fit <- limma::eBayes(limma_fit)
      tstats[[adjust_name]] <- modified_fit[["t"]]
      ##names(tstats[[counter]]) <- as.character(1:dim(data)[1])
      catplot_together <- NULL
      if (isTRUE(do_catplots)) {
        if (!isTRUE("ffpe" %in% .packages(all.available=TRUE))) {
          ## ffpe has some requirements which do not install all the time.
          tt <- please_install("ffpe")
        }
        if (isTRUE("ffpe" %in% .packages(all.available=TRUE))) {
          catplots[[adjust_name]] <- ffpe::CATplot(
                                             rank(tstats[[adjust_name]]), rank(null_tstat),
                                             maxrank=1000, make.plot=TRUE)
        } else {
          catplots[[adjust_name]] <- NULL
        }
      }
    }
  } ## End for a in 2:length(adjustments)

  ## Final catplot plotting, if necessary.
  if (isTRUE(do_catplots)) {
    catplot_df <- as.data.frame(catplots[[1]][[2]])
    for (c in 2:length(catplots)) {
      cat <- catplots[[c]]
      catplot_df <- cbind(catplot_df, cat[["concordance"]])
    }
    colnames(catplot_df) <- names(catplots)
    catplot_df[["x"]] <- rownames(catplot_df)
    gg_catplot <- reshape2::melt(data=catplot_df, id.vars="x")
    colnames(gg_catplot) <- c("x", "adjust", "y")
    gg_catplot[["x"]] <- as.numeric(gg_catplot[["x"]])
    gg_catplot[["y"]] <- as.numeric(gg_catplot[["y"]])

    cat_plot <- ggplot(data=gg_catplot, mapping=aes_string(x="x", y="y", color="adjust")) +
      ggplot2::geom_point() +
      ggplot2::geom_jitter() +
      ggplot2::geom_line() +
      ggplot2::xlab("Rank") +
      ggplot2::ylab("Concordance") +
      ggplot2::theme_bw()
  } else {
    cat_plot <- NULL
  }

  ret <- list(
    "pca_adjust" = pca_adjust,
    "sva_supervised_adjust" = sva_supervised,
    "sva_unsupervised_adjust" = sva_unsupervised,
    "ruv_supervised_adjust" = ruv_supervised,
    "ruv_residual_adjust" = ruv_residuals,
    "ruv_empirical_adjust" = ruv_empirical,
    "adjustments" = batch_adjustments,
    "correlations" = correlations,
    "plot" = ret_plot,
    "pca_plots" = pca_plots,
    "catplots" = cat_plot)
  return(ret)
}

## EOF
