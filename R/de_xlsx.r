#' Combine portions of deseq/limma/edger table output.
#'
#' This hopefully makes it easy to compare the outputs from
#' limma/DESeq2/EdgeR on a table-by-table basis.
#'
#' @param all_pairwise_result  Output from all_pairwise().
#' @param extra_annot  Add some annotation information?
#' @param csv  On some computers (Edson!) printing to excel runs the machine oom for big data sets.
#' @param excel  Filename for the excel workbook, or null if not printed.
#' @param excel_title  Title for the excel sheet(s).  If it has the
#'     string 'YYY', that will be replaced by the contrast name.
#' @param excel_sheet  Name the excel sheet.
#' @param keepers  List of reformatted table names to explicitly keep
#'     certain contrasts in specific orders and orientations.
#' @param adjp  Perhaps you do not want the adjusted p-values for plotting?
#' @param excludes  List of columns and patterns to use for excluding genes.
#' @param include_basic  Include my stupid basic logFC tables?
#' @param add_plots  Add plots to the end of the sheets with expression values?
#' @param plot_dim  Number of inches squared for the plot if added.
#' @param compare_plots  In an attempt to save memory when printing to excel, make it possible to
#'     exclude comparison plots in the summary sheet.
#' @return Table combining limma/edger/deseq outputs.
#' @seealso \code{\link{all_pairwise}}
#' @examples
#' \dontrun{
#' pretty = combine_de_tables(big_result, table='t12_vs_t0')
#' pretty = combine_de_tables(big_result, table='t12_vs_t0', keepers=list("avsb" = c("a","b")))
#' pretty = combine_de_tables(big_result, table='t12_vs_t0', keepers=list("avsb" = c("a","b")),
#'                            excludes=list("description" = c("sno","rRNA")))
#' }
#' @export
combine_de_tables <- function(all_pairwise_result, extra_annot=NULL, csv=NULL,
                              excel=NULL, excel_title="Table SXXX: Combined Differential Expression of YYY",
                              excel_sheet="combined_DE", keepers="all",
                              excludes=NULL, adjp=TRUE,
                              include_basic=TRUE, add_plots=TRUE,
                              plot_dim=6, compare_plots=TRUE) {
    ## The ontology_shared function which creates multiple sheets works a bit differently
    ## It creates all the tables, then does a createWorkbook()
    ## Does a createWorkbook() / addWorksheet()
    ## Then a writeData() / writeDataTable() / print(plot) / insertPlot() / saveWorkbook()
    ## Lets try that here.
    retlist <- NULL

    limma <- all_pairwise_result[["limma"]]
    deseq <- all_pairwise_result[["deseq"]]
    edger <- all_pairwise_result[["edger"]]
    basic <- all_pairwise_result[["basic"]]

    make_equate <- function(lm_model) {
        coefficients <- summary(lm_model)[["coefficients"]]
        int <- signif(x=coefficients["(Intercept)", 1], digits=3)
        m <- signif(x=coefficients["first", 1], digits=3)
        ret <- NULL
        if (as.numeric(int) >= 0) {
            ret <- paste0("y = ", m, "x + ", int)
        } else {
            int <- int * -1
            ret <- paste0("y = ", m, "x - ", int)
        }
        return(ret)
    }

    ## If any of the tools failed, then we cannot plot stuff with confidence.
    if (class(limma) == "try-error") {
        add_plots <- FALSE
        compare_plots <- FALSE
        message("Limma had an error.  Not adding plots.")
    }
    if (class(deseq) == "try-error") {
        add_plots <- FALSE
        compare_plots <- FALSE
        message("DESeq2 had an error.  Not adding plots.")
    }
    if (class(edger) == "try-error") {
        add_plots <- FALSE
        compare_plots <- FALSE
        message("edgeR had an error.  Not adding plots.")
    }
    if (class(basic) == "try-error") {
        add_plots <- FALSE
        compare_plots <- FALSE
        message("Basic had an error.  Not adding plots.")
    }

    csv_basename <- NULL
    if (!is.null(csv)) {
        if (is.null(excel) | excel == FALSE) {
            csv_basename <- "excel/csv_export"
        } else {
            csv_basename <- excel
            csv_basename <- gsub(pattern="\\.xlsx", replacement="", x=csv_basename)
        }
    }

    wb <- NULL
    if (!is.null(excel) & excel != FALSE) {
        excel_dir <- dirname(excel)
        if (!file.exists(excel_dir)) {
            dir.create(excel_dir, recursive=TRUE)
        }
        if (file.exists(excel)) {
            message(paste0("Deleting the file ", excel, " before writing the tables."))
            file.remove(excel)
        }
        wb <- openxlsx::createWorkbook(creator="hpgltools")
    }

    reminder_model_cond <- all_pairwise_result[["model_cond"]]
    reminder_model_batch <- all_pairwise_result[["model_batch"]]
    reminder_extra <- all_pairwise_result[["extra_contrasts"]]
    reminder_string <- NULL
    if (class(reminder_model_batch) == "matrix") {
        ## This is currently not true, ths pvalues are only modified if we modify the data.
        ## reminder_string <- "The contrasts were performed with surrogates modeled with sva.  The p-values were therefore adjusted using an experimental f-test as per the sva documentation."
        ##message(reminder_string)
    } else if (isTRUE(reminder_model_batch) & isTRUE(reminder_model_cond)) {
        reminder_string <- "The contrasts were performed with experimental condition and batch in the model."
    } else if (isTRUE(reminder_model_cond)) {
        reminder_string <- "The contrasts were performed with only experimental condition in the model."
    } else {
        reminder_string <- "The contrasts were performed in a strange way, beware!"
    }
    message("Writing a legend of columns.")
    legend <- data.frame(rbind(
        c("", reminder_string),
        c("The first ~3-10 columns of each sheet:", "are annotations provided by our chosen annotation source for this experiment."),
        c("Next 6 columns", "The logFC and p-values reported by limma, edger, and deseq2."),
        c("limma_logfc", "The log2 fold change reported by limma."),
        c("deseq_logfc", "The log2 fold change reported by DESeq2."),
        c("edger_logfc", "The log2 fold change reported by edgeR."),
        c("limma_adjp", "The adjusted-p value reported by limma."),
        c("deseq_adjp", "The adjusted-p value reported by DESeq2."),
        c("edger_adjp", "The adjusted-p value reported by edgeR."),
        c("The next 5 columns", "Statistics generated by limma."),
        c("limma_ave", "Average log2 expression observed by limma across all samples."),
        c("limma_t", "T-statistic reported by limma given the log2FC and variances."),
        c("limma_p", "Derived from limma_t, the p-value asking 'is this logfc significant?'"),
        c("limma_b", "Use a Bayesian estimate to calculate log-odds significance instead of a student's test."),
        c("limma_q", "A q-value FDR adjustment of the p-value above."),
        c("The next 5 columns", "Statistics generated by DESeq2."),
        c("deseq_basemean", "Analagous to limma's ave column, the base mean of all samples according to DESeq2."),
        c("deseq_lfcse", "The standard error observed given the log2 fold change."),
        c("deseq_stat", "T-statistic reported by DESeq2 given the log2FC and observed variances."),
        c("deseq_p", "Resulting p-value."),
        c("deseq_q", "False-positive corrected p-value."),
        c("The next 4 columns", "Statistics generated by edgeR."),
        c("edger_logcpm", "Similar to limma's ave and DESeq2's basemean, except only including the samples in the comparison."),
        c("edger_lr", "Undocumented, I am reasonably certain it is the T-statistic calculated by edgeR."),
        c("edger_p", "The observed p-value from edgeR."),
        c("edger_q", "The observed corrected p-value from edgeR."),
        c("The next 8 columns", "Statistics generated by the basic analysis written by trey."),
        c("basic_nummed", "log2 median values of the numerator for this comparison (like edgeR's basemean)."),
        c("basic_denmed", "log2 median values of the denominator for this comparison."),
        c("basic_numvar", "Variance observed in the numerator values."),
        c("basic_denvar", "Variance observed in the denominator values."),
        c("basic_logfc", "The log2 fold change observed by the basic analysis."),
        c("basic_t", "T-statistic from basic."),
        c("basic_p", "Resulting p-value."),
        c("basic_adjp", "BH correction of the p-value."),
        c("The next 5 columns", "Summaries of the limma/deseq/edger results."),
        c("fc_meta", "The mean fold-change value of limma/deseq/edger."),
        c("fc_var", "The variance between limma/deseq/edger."),
        c("fc_varbymed", "The ratio of the variance/median (closer to 0 means better agreement.)"),
        c("p_meta", "A meta-p-value of the mean p-values."),
        c("p_var", "Variance among the 3 p-values."),
        c("The last columns: top plot left",
          "Venn diagram of the genes with logFC > 0 and p-value <= 0.05 for limma/DESeq/Edger."),
        c("The last columns: top plot right",
          "Venn diagram of the genes with logFC < 0 and p-value <= 0.05 for limma/DESeq/Edger."),
        c("The last columns: second plot",
          "Scatter plot of the voom-adjusted/normalized counts for each coefficient."),
        c("The last columns: third plot",
          "Scatter plot of the adjusted/normalized counts for each coefficient from edgeR."),
        c("The last columns: fourth plot",
          "Scatter plot of the adjusted/normalized counts for each coefficient from DESeq."),
        c("", "If this data was adjusted with sva, then check for a sheet 'original_pvalues' at the end.")
    ))

    colnames(legend) <- c("column name", "column definition")
    xls_result <- write_xls(wb, data=legend, sheet="legend", rownames=FALSE,
                            title="Columns used in the following tables.")

    annot_df <- Biobase::fData(all_pairwise_result[["input"]][["expressionset"]])
    if (!is.null(extra_annot)) {
        annot_df <- merge(annot_df, extra_annot, by="row.names", all.x=TRUE)
        rownames(annot_df) <- annot_df[["Row.names"]]
        annot_df <- annot_df[, -1, drop=FALSE]
    }

    combo <- list()
    limma_plots <- list()
    edger_plots <- list()
    deseq_plots <- list()
    sheet_count <- 0
    de_summaries <- data.frame()

    if (class(keepers) == "list") {
        ## Then keep specific tables in specific orientations.
        a <- 0
        keeper_len <- length(names(keepers))
        table_names <- list()
        for (name in names(keepers)) {
            a <- a + 1
            message(paste0("Working on ", a, "/", keeper_len, ": ",  name))
            sheet_count <- sheet_count + 1
            numerator <- keepers[[name]][1]
            denominator <- keepers[[name]][2]
            same_string <- numerator
            inverse_string <- numerator
            if (!is.na(denominator)) {
                same_string <- paste0(numerator, "_vs_", denominator)
                inverse_string <- paste0(denominator, "_vs_", numerator)
            }
            dat <- NULL
            plt <- NULL
            summary <- NULL
            found <- 0
            found_table <- NULL
            do_inverse <- NULL
            limma_plt <- NULL
            edger_plt <- NULL
            deseq_plt <- NULL

            contrasts_performed <- NULL
            if (class(limma) != "try-error") {
                contrasts_performed <- limma[["contrasts_performed"]]
            } else if (class(edger) != "try-error") {
                contrasts_performed <- edger[["contrasts_performed"]]
            } else if (class(deseq) != "try-error") {
                contrasts_performed <- deseq[["contrasts_performed"]]
            } else if (class(basic) != "try-error") {
                contrasts_performed <- basic[["contrasts_performed"]]
            } else {
                stop("None of the DE tools appear to have worked.")
            }
            for (tab in limma[["contrasts_performed"]]) {
                if (tab == same_string) {
                    do_inverse <- FALSE
                    found <- found + 1
                    found_table <- same_string
                    message(paste0("Found table with ", same_string))
                } else if (tab == inverse_string) {
                    do_inverse <- TRUE
                    found <- found + 1
                    found_table <- inverse_string
                    message(paste0("Found inverse table with ", inverse_string))
                }
            }
            if (class(limma) == "try-error") {
                limma <- NULL
            }
            if (class(deseq) == "try-error") {
                deseq <- NULL
            }
            if (class(edger) == "try-error") {
                edger <- NULL
            }
            if (class(basic) == "try-error") {
                basic <- NULL
            }
            if (found > 0) {
                combined <- create_combined_table(limma, edger, deseq, basic,
                                                  found_table, inverse=do_inverse,
                                                  adjp=adjp, annot_df=annot_df,
                                                  include_basic=include_basic, excludes=excludes)
                dat <- combined[["data"]]
                summary <- combined[["summary"]]
                if (isTRUE(do_inverse)) {
                    limma_try <- try(sm(extract_coefficient_scatter(limma, type="limma", x=denominator, y=numerator)), silent=TRUE)
                    if (class(limma_try) == "list") {
                        limma_plt <- limma_try
                    } else {
                        limma_plt <- NULL
                    }
                    edger_try <- try(sm(extract_coefficient_scatter(edger, type="edger", x=denominator, y=numerator)), silent=TRUE)
                    if (class(edger_try) == "list") {
                        edger_plt <- edger_try
                    } else {
                        edger_plt <- NULL
                    }
                    deseq_try <- try(sm(extract_coefficient_scatter(deseq, type="deseq", x=denominator, y=numerator)), silent=TRUE)
                    if (class(deseq_try) == "list") {
                        deseq_plt <- deseq_try
                    } else {
                        deseq_plt <- NULL
                    }
                } else {
                    limma_try <- try(sm(extract_coefficient_scatter(limma, type="limma", x=numerator, y=denominator)), silent=TRUE)
                    if (class(limma_try) == "list") {
                        limma_plt <- limma_try
                    } else {
                        limma_plt <- NULL
                    }
                    edger_try <- try(sm(extract_coefficient_scatter(edger, type="edger", x=numerator, y=denominator)), silent=TRUE)
                    if (class(edger_try) == "list") {
                        edger_plt <- edger_try
                    } else {
                        edger_plt <- NULL
                    }
                    deseq_try <- try(sm(extract_coefficient_scatter(deseq, type="deseq", x=numerator, y=denominator)), silent=TRUE)
                    if (class(deseq_try) == "list") {
                        deseq_plt <- deseq_try
                    } else {
                        deseq_plt <- NULL
                    }
                }
            } ## End checking that we found the numerator/denominator
            else {
                warning(paste0("Did not find either ", same_string, " nor ", inverse_string, "."))
            }
            combo[[name]] <- dat
            limma_plots[[name]] <- limma_plt
            edger_plots[[name]] <- edger_plt
            deseq_plots[[name]] <- deseq_plt
            de_summaries <- rbind(de_summaries, summary)
            table_names[[a]] <- summary[["table"]]
        }
        ## If you want all the tables in a dump
    }

    else if (class(keepers) == "character" & keepers == "all") {
        a <- 0
        names_length <- length(names(edger[["contrast_list"]]))
        table_names <- names(edger[["contrast_list"]])
        for (tab in names(edger[["contrast_list"]])) {
            a <- a + 1
            message(paste0("Working on table ", a, "/", names_length, ": ", tab))
            sheet_count <- sheet_count + 1
            combined <- create_combined_table(limma, edger, deseq, basic,
                                              tab, annot_df=annot_df,
                                              include_basic=include_basic, excludes=excludes)
            de_summaries <- rbind(de_summaries, combined[["summary"]])
            combo[[tab]] <- combined[["data"]]
            splitted <- strsplit(x=tab, split="_vs_")
            xname <- splitted[[1]][1]
            yname <- splitted[[1]][2]
            limma_plots[[tab]] <- sm(extract_coefficient_scatter(limma, type="limma", x=xname, y=yname))
            edger_plots[[tab]] <- sm(extract_coefficient_scatter(edger, type="edger", x=xname, y=yname))
            deseq_plots[[tab]] <- sm(extract_coefficient_scatter(deseq, type="deseq", x=xname, y=yname))
        }

        ## Or a single specific table
    }

    else if (class(keepers) == "character") {
        table <- keepers
        sheet_count <- sheet_count + 1
        if (table %in% names(edger[["contrast_list"]])) {
            message(paste0("I found ", table, " in the available contrasts."))
        } else {
            message(paste0("I did not find ", table, " in the available contrasts."))
            message(paste0("The available tables are: ", names(edger[["contrast_list"]])))
            table <- names(edger[["contrast_list"]])[[1]]
            message(paste0("Choosing the first table: ", table))
        }
        combined <- create_combined_table(limma, edger, deseq, basic,
                                          table, annot_df=annot_df,
                                          include_basic=include_basic, excludes=excludes)
        combo[[table]] <- combined[["data"]]
        splitted <- strsplit(x=tab, split="_vs_")
        de_summaries <- rbind(de_summaries, combined[["summary"]])
        table_names[[a]] <- combined[["summary"]][["table"]]
        xname <- splitted[[1]][1]
        yname <- splitted[[1]][2]
        limma_plots[[name]] <- sm(extract_coefficient_scatter(limma, type="limma", x=xname, y=yname))
        edger_plots[[name]] <- sm(extract_coefficient_scatter(edger, type="edger", x=xname, y=yname))
        deseq_plots[[name]] <- sm(extract_coefficient_scatter(deseq, type="deseq", x=xname, y=yname))
    } else {
        stop("I don't know what to do with your specification of tables to keep.")
    } ## End different types of things to keep.


    venns <- list()
    comp <- NULL
    if (!is.null(excel) & excel != FALSE) {
        ## Starting a new counter of sheets.
        count <- 0
        for (tab in names(combo)) {
            count <- count + 1
            ddd <- combo[[count]]
            oddness = summary(ddd) ## until I did this I was getting errors I am guessing devtools::load_all() isn't clearing everything
            final_excel_title <- gsub(pattern='YYY', replacement=tab, x=excel_title)
            xls_result <- write_xls(data=ddd, wb=wb, sheet=tab, title=final_excel_title)
            if (!is.null(csv)) {
                csv_filename <- paste0(csv_basename, "_", tab, ".csv")
                write.csv(x=ddd, file=csv_filename)
            }
            if (isTRUE(add_plots)) {
                ## Text on row 1, plots from 2-17 (15 rows)
                plot_column <- xls_result[["end_col"]] + 2
                message(paste0("Adding venn plots for ", names(combo)[[count]], "."))
                openxlsx::writeData(wb, tab, x="Venn of p-value up genes.", startRow=1, startCol=plot_column)
                venn_list <- try(de_venn(ddd, adjp=adjp), silent=TRUE)
                if (class(venn_list) != "try-error") {
                    up_plot <- venn_list[["up_noweight"]]
                    tt <- try(print(up_plot))
                    tt <- try(openxlsx::insertPlot(wb, tab, width=(plot_dim / 2), height=(plot_dim / 2),
                                                   startCol=plot_column, startRow=2, fileType="png",
                                                   units="in"))
                    openxlsx::writeData(wb, tab, x="Venn of p-value down genes.", startRow=1, startCol=plot_column + 4)
                    down_plot <- venn_list[["down_noweight"]]
                    tt <- try(print(down_plot))
                    tt <- try(openxlsx::insertPlot(wb, tab, width=(plot_dim / 2), height=(plot_dim / 2),
                                                   startCol=plot_column + 4, startRow=2, fileType="png",
                                                   units="in"))
                    venns[[tab]] <- venn_list
                }

                ## Text on row 18, plots from 19-49 (30 rows)
                plt <- limma_plots[count][[1]]
                if (class(plt) != "try-error" & !is.null(plt)) {
                    printme <- paste0("Limma expression coefficients for ", names(combo)[[count]], "; R^2: ",
                                      signif(x=plt[["lm_rsq"]], digits=3), "; equation: ",
                                      make_equate(plt[["lm_model"]]))
                    message(printme)
                    openxlsx::writeData(wb, tab, x=printme, startRow=18, startCol=plot_column)
                    tt <- try(print(plt[["scatter"]]))
                    tt <- try(openxlsx::insertPlot(wb, tab, width=plot_dim, height=plot_dim,
                                                   startCol=plot_column, startRow=19, fileType="png",
                                                   units="in"))
                }
                ## Text on row 50, plots from 51-81
                plt <- edger_plots[count][[1]] ##FIXME this is suspicious
                if (class(plt) != "try-error" & !is.null(plt)) {
                    printme <- paste0("Edger expression coefficients for ", names(combo)[[count]], "; R^2: ",
                                      signif(plt[["lm_rsq"]], digits=3), "; equation: ",
                                      make_equate(plt[["lm_model"]]))
                    message(printme)
                    openxlsx::writeData(wb, tab, x=printme, startRow=50, startCol=plot_column)
                    tt <- try(print(plt[["scatter"]]))
                    tt <- try(openxlsx::insertPlot(wb, tab, width=plot_dim, height=plot_dim,
                                                   startCol=plot_column, startRow=51, fileType="png",
                                                   units="in"))
                }
                ## Text on 81, plots 82-112
                plt <- deseq_plots[count][[1]]
                if (class(plt) != "try-error" & !is.null(plt)) {
                    printme <- paste0("DESeq2 expression coefficients for ", names(combo)[[count]], "; R^2: ",
                                      signif(plt[["lm_rsq"]], digits=3), "; equation: ",
                                      make_equate(plt[["lm_model"]]))
                    message(printme)
                    openxlsx::writeData(wb, tab, x=printme, startRow=81, startCol=plot_column)
                    tt <- try(print(plt[["scatter"]]))
                    tt <- try(openxlsx::insertPlot(wb, tab, width=plot_dim, height=plot_dim,
                                                   startCol=plot_column, startRow=82, fileType="png",
                                                   units="in"))
                }
            }
        }  ## End for loop
        count <- count + 1

        message("Writing summary information.")
        if (isTRUE(compare_plots)) {
            ## Add a graph on the final sheet of how similar the result types were
            comp_summary <- all_pairwise_result[["comparison"]][["comp"]]
            comp_plot <- all_pairwise_result[["comparison"]][["heat"]]
            de_summaries <- as.data.frame(de_summaries)
            rownames(de_summaries) <- table_names
            xls_result <- write_xls(wb, data=de_summaries, sheet="pairwise_summary",
                                    title="Summary of contrasts.")
            new_row <- xls_result[["end_row"]] + 2
            xls_result <- write_xls(wb, data=comp_summary, sheet="pairwise_summary",
                                    title="Pairwise correlation coefficients among differential expression tools.",
                                    start_row=new_row)
            new_row <- xls_result[["end_row"]] + 2
            message(paste0("Attempting to add the comparison plot to pairwise_summary at row: ", new_row + 1, " and column: ", 1))
            if (class(comp_plot) == "recordedplot") {
                tt <- try(print(comp_plot))
                tt <- try(openxlsx::insertPlot(wb, "pairwise_summary", width=6, height=6,
                                               startRow=new_row + 1, startCol=1, fileType="png", units="in"))
            }
            logfc_comparisons <- try(compare_logfc_plots(combo), silent=TRUE)
            if (class(logfc_comparisons) != "try-error") {
                logfc_names <- names(logfc_comparisons)
                new_row <- new_row + 2
                for (c in 1:length(logfc_comparisons)) {
                    new_row <- new_row + 32
                    le <- logfc_comparisons[[c]][["le"]]
                    ld <- logfc_comparisons[[c]][["ld"]]
                    de <- logfc_comparisons[[c]][["de"]]
                    tmpcol <- 1
                    openxlsx::writeData(wb, "pairwise_summary", x=paste0("Comparing DE tools for the comparison of: ", logfc_names[c]),
                                        startRow=new_row - 2, startCol=tmpcol)
                    openxlsx::writeData(wb, "pairwise_summary", x="Log2FC(Limma vs. EdgeR)", startRow=new_row - 1, startCol=tmpcol)
                    tt <- try(print(le))
                    tt <- try(openxlsx::insertPlot(wb, "pairwise_summary", width=6, height=6,
                                                   startRow=new_row, startCol=tmpcol, fileType="png",
                                                   units="in"))
                    tmpcol <- 8
                    openxlsx::writeData(wb, "pairwise_summary", x="Log2FC(Limma vs. DESeq2)", startRow=new_row - 1, startCol=tmpcol)
                    tt <- try(print(ld))
                    tt <- try(openxlsx::insertPlot(wb, "pairwise_summary", width=6, height=6,
                                                   startRow=new_row, startCol=tmpcol, fileType="png",
                                                   units="in"))
                    tmpcol <- 15
                    openxlsx::writeData(wb, "pairwise_summary", x="Log2FC(DESeq2 vs. EdgeR)", startRow=new_row - 1, startCol=tmpcol)
                    tt <- try(print(de))
                    tt <- try(openxlsx::insertPlot(wb, "pairwise_summary", width=6, height=6,
                                                   startRow=new_row, startCol=tmpcol, fileType="png",
                                                   units="in"))
                }
            } ## End checking if we could compare the logFC/P-values
        } ## End if compare_plots is TRUE

        if (!is.null(all_pairwise_result[["original_pvalues"]])) {
            message("Appending a data frame of the original pvalues before sva messed with them.")
            xls_result <- write_xls(wb, data=all_pairwise_result[["original_pvalues"]], sheet="original_pvalues",
                                    title="Original pvalues for all contrasts before sva adjustment.",
                                    start_row=1)
        }


        message("Performing save of the workbook.")
        save_result <- try(openxlsx::saveWorkbook(wb, excel, overwrite=TRUE))
        if (class(save_result) == "try-error") {
            message("Saving xlsx failed.  Rerunning now with arguments to save to csv files.")
            retlist <- combine_de_tables(all_pairwise_result,
                                         extra_annot=extra_annot,
                                         csv=excel,
                                         excel=NULL,
                                         excel_title=excel_title,
                                         excel_sheet=excel_sheet,
                                         keepers=keepers,
                                         include_basic=include_basic,
                                         add_plots=FALSE,
                                         compare_plots=FALSE)
        }
    } ## End if !is.null(excel)

    ret <- NULL
    if (is.null(retlist)) {
        ret <- list(
            "data" = combo,
            "limma_plots" = limma_plots,
            "edger_plots" = edger_plots,
            "deseq_plots" = deseq_plots,
            "comp_plot" = comp,
            "venns" = venns,
            "de_summary" = de_summaries)
    } else {
        ret <- retlist
    }
    return(ret)
}

#' Given a limma, edger, and deseq table, combine them into one.
#'
#' This combines the outputs from the various differential expression
#' tools and formalizes some column names to make them a little more
#' consistent.
#'
#' @param li  Limma output table.
#' @param ed  Edger output table.
#' @param de  Deseq2 output table.
#' @param ba  Basic output table.
#' @param table_name  Name of the table to merge.
#' @param annot_df  Add some annotation information?
#' @param inverse  Invert the fold changes?
#' @param adjp  Use adjusted p-values?
#' @param include_basic  Include the basic table?
#' @param fc_cutoff  Preferred logfoldchange cutoff.
#' @param p_cutoff  Preferred pvalue cutoff.
#' @param excludes  Set of genes to exclude from the output.
#' @return List containing a) Dataframe containing the merged
#'     limma/edger/deseq/basic tables, and b) A summary of how many
#'     genes were observed as up/down by output table.
#' @export
create_combined_table <- function(li, ed, de, ba,
                                  table_name, annot_df=NULL,
                                  inverse=FALSE, adjp=TRUE,
                                  include_basic=TRUE, fc_cutoff=1,
                                  p_cutoff=0.05, excludes=NULL) {
    li <- li[["all_tables"]][[table_name]]
    if (is.null(li)) {
        li <- data.frame("limma_logfc" = 0, "limma_ave" = 0, "limma_t" = 0,
                         "limma_p" = 0, "limma_adjp" = 0, "limma_b" = 0, "limma_q" = 0)
    }
    de <- de[["all_tables"]][[table_name]]
    if (is.null(de)) {
        de <- data.frame("deseq_basemean" = 0, "deseq_logfc" = 0, "deseq_lfcse" = 0,
                         "deseq_stat" = 0, "deseq_p" = 0, "deseq_adjp" = 0, "deseq_q" = 0)
    }
    ed <- ed[["all_tables"]][[table_name]]
    if (is.null(ed)) {
        ed <- data.frame("edger_logfc" = 0, "edger_logcpm" = 0, "edger_lr" = 0,
                         "edger_p" = 0, "edger_adjp" = 0, "edger_q" = 0)
    }
    ba <- ba[["all_tables"]][[table_name]]
    if (is.null(ba)) {
        ba <- data.frame("numerator_median" = 0, "denominator_median" = 0, "numerator_var" = 0,
                         "denominator_var" = 0, "logFC" = 0, "t" = 0, "p" = 0, adjp=0)
    }

    colnames(li) <- c("limma_logfc","limma_ave","limma_t","limma_p","limma_adjp","limma_b","limma_q")
    li <- li[, c("limma_logfc","limma_ave","limma_t","limma_b","limma_p","limma_adjp","limma_q")]
    colnames(de) <- c("deseq_basemean","deseq_logfc","deseq_lfcse","deseq_stat","deseq_p","deseq_adjp","deseq_q")
    de <- de[, c("deseq_logfc","deseq_basemean","deseq_lfcse","deseq_stat","deseq_p","deseq_adjp","deseq_q")]
    colnames(ed) <- c("edger_logfc","edger_logcpm","edger_lr","edger_p","edger_adjp","edger_q")

    ba <- ba[, c("numerator_median","denominator_median","numerator_var",
                 "denominator_var", "logFC", "t", "p", "adjp")]
    colnames(ba) <- c("basic_nummed","basic_denmed", "basic_numvar", "basic_denvar",
                      "basic_logfc", "basic_t", "basic_p", "basic_adjp")

    lidt <- data.table::as.data.table(li)
    lidt[["rownames"]] <- rownames(li)
    dedt <- data.table::as.data.table(de)
    dedt[["rownames"]] <- rownames(de)
    eddt <- data.table::as.data.table(ed)
    eddt[["rownames"]] <- rownames(ed)
    badt <- data.table::as.data.table(ba)
    badt[["rownames"]] <- rownames(ba)
    comb <- merge(lidt, dedt, by="rownames", all.x=TRUE)
    comb <- merge(comb, eddt, by="rownames", all.x=TRUE)
    if (isTRUE(include_basic)) {
        comb <- merge(comb, badt, by="rownames", all.x=TRUE)
    }
    comb <- as.data.frame(comb)
    rownames(comb) <- comb[["rownames"]]
    comb <- comb[, -1, drop=FALSE]
    rm(lidt)
    rm(dedt)
    rm(eddt)
    rm(badt)
    comb[is.na(comb)] <- 0
    if (isTRUE(include_basic)) {
        comb <- comb[, c("limma_logfc", "deseq_logfc", "edger_logfc",
                         "limma_adjp", "deseq_adjp", "edger_adjp",
                         "limma_ave", "limma_t", "limma_p", "limma_b", "limma_q",
                         "deseq_basemean", "deseq_lfcse", "deseq_stat", "deseq_p", "deseq_q",
                         "edger_logcpm", "edger_lr", "edger_p", "edger_q",
                         "basic_nummed", "basic_denmed", "basic_numvar", "basic_denvar",
                         "basic_logfc", "basic_t", "basic_p", "basic_adjp")]
    } else {
        comb <- comb[, c("limma_logfc", "deseq_logfc", "edger_logfc",
                         "limma_adjp", "deseq_adjp", "edger_adjp",
                         "limma_ave", "limma_t", "limma_p", "limma_b", "limma_q",
                         "deseq_basemean", "deseq_lfcse", "deseq_stat", "deseq_p", "deseq_q",
                         "edger_logcpm","edger_lr","edger_p","edger_q")]
    }
    if (isTRUE(inverse)) {
        comb[["limma_logfc"]] <- comb[["limma_logfc"]] * -1.0
        comb[["deseq_logfc"]] <- comb[["deseq_logfc"]] * -1.0
        comb[["deseq_stat"]] <- comb[["deseq_stat"]] * -1.0
        comb[["edger_logfc"]] <- comb[["edger_logfc"]] * -1.0
        if (isTRUE(include_basic)) {
            comb[["basic_logfc"]] <- comb[["basic_logfc"]] * -1.0
        }
    }
    ## I made an odd choice in a moment to normalize.quantils the combined fold changes
    ## This should be reevaluated
    temp_fc <- cbind(as.numeric(comb[["limma_logfc"]]),
                     as.numeric(comb[["edger_logfc"]]),
                     as.numeric(comb[["deseq_logfc"]]))
    temp_fc <- preprocessCore::normalize.quantiles(as.matrix(temp_fc))
    comb[["fc_meta"]] <- rowMeans(temp_fc, na.rm=TRUE)
    comb[["fc_var"]] <- genefilter::rowVars(temp_fc, na.rm=TRUE)
    comb[["fc_varbymed"]] <- comb$fc_var / comb$fc_meta
    temp_p <- cbind(as.numeric(comb[["limma_p"]]),
                    as.numeric(comb[["edger_p"]]),
                    as.numeric(comb[["deseq_p"]]))
    comb[["p_meta"]] <- rowMeans(temp_p, na.rm=TRUE)
    comb[["p_var"]] <- genefilter::rowVars(temp_p, na.rm=TRUE)
    comb[["fc_meta"]] <- signif(x=comb[["fc_meta"]], digits=4)
    comb[["fc_var"]] <- format(x=comb[["fc_var"]], digits=4, scientific=TRUE)
    comb[["fc_varbymed"]] <- format(x=comb[["fc_varbymed"]], digits=4, scientific=TRUE)
    comb[["p_var"]] <- format(x=comb[["p_var"]], digits=4, scientific=TRUE)
    comb[["p_meta"]] <- format(x=comb[["p_meta"]], digits=4, scientific=TRUE)
    if (!is.null(annot_df)) {
        ## colnames(annot_df) <- gsub("[[:digit:]]", "", colnames(annot_df))
        colnames(annot_df) <- gsub("[[:punct:]]", "", colnames(annot_df))
        comb <- merge(annot_df, comb, by="row.names", all.y=TRUE)
        rownames(comb) <- comb[["Row.names"]]
        comb <- comb[, -1, drop=FALSE]
        colnames(comb) <- make.names(tolower(colnames(comb)), unique=TRUE)
    }

    ## Exclude rows based on a list of unwanted columns/strings
    if (!is.null(excludes)) {
        for (colnum in 1:length(excludes)) {
            col <- names(excludes)[colnum]
            for (exclude_num in 1:length(excludes[[col]])) {
                exclude <- excludes[[col]][exclude_num]
                remove_column <- comb[[col]]
                remove_idx <- grep(pattern=exclude, x=remove_column, perl=TRUE, invert=TRUE)
                removed_num <- sum(as.numeric(remove_idx))
                message(paste0("Removed ", removed_num, " genes using ", exclude, " as a string against column ", remove_column, "."))
                comb <- comb[remove_idx, ]
            }  ## End iterating through every string to exclude
        }  ## End iterating through every element of the exclude list
    }

    up_fc <- fc_cutoff
    down_fc <- -1.0 * fc_cutoff
    summary_table_name <- table_name
    if (isTRUE(inverse)) {
        summary_table_name <- paste0(summary_table_name, "-inverted")
    }
    limma_p_column <- "limma_adjp"
    deseq_p_column <- "deseq_adjp"
    edger_p_column <- "edger_adjp"
    if (!isTRUE(adjp)) {
        limma_p_column <- "limma_p"
        deseq_p_column <- "deseq_p"
        edger_p_column <- "edger_p"
    }
    summary_lst <- list(
        "table" = summary_table_name,
        "total" = nrow(comb),
        "limma_up" = sum(comb[["limma_logfc"]] >= up_fc),
        "limma_sigup" = sum(comb[["limma_logfc"]] >= up_fc & as.numeric(comb[[limma_p_column]]) <= p_cutoff),
        "deseq_up" = sum(comb[["deseq_logfc"]] >= up_fc),
        "deseq_sigup" = sum(comb[["deseq_logfc"]] >= up_fc & as.numeric(comb[[deseq_p_column]]) <= p_cutoff),
        "edger_up" = sum(comb[["edger_logfc"]] >= up_fc),
        "edger_sigup" = sum(comb[["edger_logfc"]] >= up_fc & as.numeric(comb[[edger_p_column]]) <= p_cutoff),
        "basic_up" = sum(comb[["basic_logfc"]] >= up_fc),
        "basic_sigup" = sum(comb[["basic_logfc"]] >= up_fc & as.numeric(comb[["basic_p"]]) <= p_cutoff),
        "limma_down" = sum(comb[["limma_logfc"]] <= down_fc),
        "limma_sigdown" = sum(comb[["limma_logfc"]] <= down_fc & as.numeric(comb[[limma_p_column]]) <= p_cutoff),
        "deseq_down" = sum(comb[["deseq_logfc"]] <= down_fc),
        "deseq_sigdown" = sum(comb[["deseq_logfc"]] <= down_fc & as.numeric(comb[[deseq_p_column]]) <= p_cutoff),
        "edger_down" = sum(comb[["edger_logfc"]] <= down_fc),
        "edger_sigdown" = sum(comb[["edger_logfc"]] <= down_fc & as.numeric(comb[[edger_p_column]]) <= p_cutoff),
        "basic_down" = sum(comb[["basic_logfc"]] <= down_fc),
        "basic_sigdown" = sum(comb[["basic_logfc"]] <= down_fc & as.numeric(comb[["basic_p"]]) <= p_cutoff),
        "meta_up" = sum(comb[["fc_meta"]] >= up_fc),
        "meta_sigup" = sum(comb[["fc_meta"]] >= up_fc & as.numeric(comb[["p_meta"]]) <= p_cutoff),
        "meta_down" = sum(comb[["fc_meta"]] <= down_fc),
        "meta_sigdown" = sum(comb[["fc_meta"]] <= down_fc & as.numeric(comb[["p_meta"]]) <= p_cutoff)
        )

    ret <- list(
        "data" = comb,
        "summary" = summary_lst)
    return(ret)
}

#' Alias for extract_significant_genes because I am dumb.
#'
#' @param ... The parameters for extract_significant_genes()
#' @return  It should return a reminder for me to remember my function names or change them to
#'     something not stupid.
#' @export
extract_siggenes <- function(...) { extract_significant_genes(...) }
#' Extract the sets of genes which are significantly up/down regulated
#' from the combined tables.
#'
#' Given the output from combine_de_tables(), extract the genes in
#' which we have the greatest likely interest, either because they
#' have the largest fold changes, lowest p-values, fall outside a
#' z-score, or are at the top/bottom of the ranked list.
#'
#' @param combined  Output from combine_de_tables().
#' @param according_to  What tool(s) decide 'significant?'  One may use
#'        the deseq, edger, limma, basic, meta, or all.
#' @param fc  Log fold change to define 'significant'.
#' @param p  (Adjusted)p-value to define 'significant'.
#' @param sig_bar  Add bar plots describing various cutoffs of 'significant'?
#' @param z  Z-score to define 'significant'.
#' @param n  Take the top/bottom-n genes.
#' @param ma  Add ma plots to the sheets of 'up' genes?
#' @param p_type  use an adjusted p-value?
#' @param csv  Write csv instead of xlsx when running OOM.
#' @param excel  Write the results to this excel file, or NULL.
#' @param siglfc_cutoffs  Set of cutoffs used to define levels of 'significant.'
#' @return The set of up-genes, down-genes, and numbers therein.
#' @seealso \code{\link{combine_de_tables}}
#' @export
extract_significant_genes <- function(combined,
                                      according_to="all",
                                      fc=1.0, p=0.05, sig_bar=TRUE,
                                      z=NULL, n=NULL, ma=TRUE,
                                      p_type="adj",
                                      csv=NULL, excel="excel/significant_genes.xlsx",
                                      siglfc_cutoffs=c(0,1,2)) {
    num_tables <- 0
    table_names <- NULL
    all_tables <- NULL
    if (!is.null(combined[["data"]])) {
        ## Then this is the result of combine_de_tables()
        num_tables <- length(names(combined[["data"]]))
        table_names <- names(combined[["data"]])
        all_tables <- combined[["data"]]
    } else {
        ## Then this is the result of all_pairwise()
        num_tables <- length(combined[["contrasts"]])
        table_names <- combined[["contrasts"]]
        all_tables <- combined[["all_tables"]]
    }
    trimmed_up <- list()
    trimmed_down <- list()
    up_titles <- list()
    down_titles <- list()
    sig_list <- list()
    title_append <- ""
    if (!is.null(fc)) {
        title_append <- paste0(title_append, " log2fc><", fc)
    }
    if (!is.null(p)) {
        title_append <- paste0(title_append, " p<", p)
    }
    if (!is.null(z)) {
        title_append <- paste0(title_append, " z><", z)
    }
    if (!is.null(n)) {
        title_append <- paste0(title_append, " top|bottom n=", n)
    }

    table_count <- 0
    if (according_to == "all") {
        according_to <- c("limma","edger","deseq","basic")
    }

    wb <- NULL
    if (class(excel) == "character") {
        message("Writing a legend of columns.")
        wb <- openxlsx::createWorkbook(creator="hpgltools")
        legend <- data.frame(rbind(
            c("The first ~3-10 columns of each sheet:", "are annotations provided by our chosen annotation source for this experiment."),
            c("Next 6 columns", "The logFC and p-values reported by limma, edger, and deseq2."),
            c("limma_logfc", "The log2 fold change reported by limma."),
            c("deseq_logfc", "The log2 fold change reported by DESeq2."),
            c("edger_logfc", "The log2 fold change reported by edgeR."),
            c("limma_adjp", "The adjusted-p value reported by limma."),
            c("deseq_adjp", "The adjusted-p value reported by DESeq2."),
            c("edger_adjp", "The adjusted-p value reported by edgeR."),
            c("The next 5 columns", "Statistics generated by limma."),
            c("limma_ave", "Average log2 expression observed by limma across all samples."),
            c("limma_t", "T-statistic reported by limma given the log2FC and variances."),
            c("limma_p", "Derived from limma_t, the p-value asking 'is this logfc significant?'"),
            c("limma_b", "Use a Bayesian estimate to calculate log-odds significance instead of a student's test."),
            c("limma_q", "A q-value FDR adjustment of the p-value above."),
            c("The next 5 columns", "Statistics generated by DESeq2."),
            c("deseq_basemean", "Analagous to limma's ave column, the base mean of all samples according to DESeq2."),
            c("deseq_lfcse", "The standard error observed given the log2 fold change."),
            c("deseq_stat", "T-statistic reported by DESeq2 given the log2FC and observed variances."),
            c("deseq_p", "Resulting p-value."),
            c("deseq_q", "False-positive corrected p-value."),
            c("The next 4 columns", "Statistics generated by edgeR."),
            c("edger_logcpm", "Similar to limma's ave and DESeq2's basemean, except only including the samples in the comparison."),
            c("edger_lr", "Undocumented, I am reasonably certain it is the T-statistic calculated by edgeR."),
            c("edger_p", "The observed p-value from edgeR."),
            c("edger_q", "The observed corrected p-value from edgeR."),
            c("The next 8 columns", "Statistics generated by the basic analysis written by trey."),
            c("basic_nummed", "log2 median values of the numerator for this comparison (like edgeR's basemean)."),
            c("basic_denmed", "log2 median values of the denominator for this comparison."),
            c("basic_numvar", "Variance observed in the numerator values."),
            c("basic_denvar", "Variance observed in the denominator values."),
            c("basic_logfc", "The log2 fold change observed by the basic analysis."),
            c("basic_t", "T-statistic from basic."),
            c("basic_p", "Resulting p-value."),
            c("basic_adjp", "BH correction of the p-value."),
            c("The next 5 columns", "Summaries of the limma/deseq/edger results."),
            c("fc_meta", "The mean fold-change value of limma/deseq/edger."),
            c("fc_var", "The variance between limma/deseq/edger."),
            c("fc_varbymed", "The ratio of the variance/median (closer to 0 means better agreement.)"),
            c("p_meta", "A meta-p-value of the mean p-values."),
            c("p_var", "Variance among the 3 p-values."),
            c("The last columns: top plot left",
              "Venn diagram of the genes with logFC > 0 and p-value <= 0.05 for limma/DESeq/Edger."),
            c("The last columns: top plot right",
              "Venn diagram of the genes with logFC < 0 and p-value <= 0.05 for limma/DESeq/Edger."),
            c("The last columns: second plot",
              "Scatter plot of the voom-adjusted/normalized counts for each coefficient."),
            c("The last columns: third plot",
              "Scatter plot of the adjusted/normalized counts for each coefficient from edgeR."),
            c("The last columns: fourth plot",
              "Scatter plot of the adjusted/normalized counts for each coefficient from DESeq."),
            c("", "If this data was adjusted with sva, then check for a sheet 'original_pvalues' at the end.")
        ))

        colnames(legend) <- c("column name", "column definition")
        xls_result <- write_xls(wb, data=legend, sheet="legend", rownames=FALSE,
                                title="Columns used in the following tables.")
    }

    ret <- list()
    summary_count <- 0
    sheet_count <- 0
    for (according in according_to) {
        summary_count <- summary_count + 1
        ret[[according]] <- list()
        ma_plots <- list()
        change_counts_up <- list()
        change_counts_down <- list()
        for (table_name in table_names) {
            message(paste0("Writing excel data sheet ", table_count, "/", num_tables, ": ", table_name))
            table_count <- table_count + 1
            table <- all_tables[[table_name]]
            fc_column <- paste0(according, "_logfc")
            p_column <- paste0(according, "_adjp")
            if (p_type != "adj") {
                p_column <- paste0(according, "_p")
            }
            if (isTRUE(ma)) {
                single_ma <- NULL
                if (according == "limma") {
                    single_ma <- extract_de_ma(combined, type="limma",
                                               table=table_name, fc=fc,  pval_cutoff=p)
                    single_ma <- single_ma[["plot"]]
                } else if (according == "deseq") {
                    single_ma <- extract_de_ma(combined, type="deseq",
                                               table=table_name, fc=fc, pval_cutoff=p)
                    single_ma <- single_ma[["plot"]]
                } else if (according == "edger") {
                    single_ma <- extract_de_ma(combined, type="edger",
                                               table=table_name, fc=fc, pval_cutoff=p)
                    single_ma <- single_ma[["plot"]]
                } else if (according == "basic") {
                    ##single_ma <- extract_de_ma(combined, type="basic",
                    ##                        table=table_name, fc=fc, pval_cutoff=p)
                    single_ma <- NULL
                } else {
                    message("Do not know this according type.")
                }
                ma_plots[[table_name]] <- single_ma
            }
            trimming <- get_sig_genes(table, fc=fc, p=p, z=z, n=n,
                                      column=fc_column, p_column=p_column)
            trimmed_up[[table_name]] <- trimming[["up_genes"]]
            change_counts_up[[table_name]] <- nrow(trimmed_up[[table_name]])
            trimmed_down[[table_name]] <- trimming[["down_genes"]]
            change_counts_down[[table_name]] <- nrow(trimmed_down[[table_name]])
            up_title <- paste0("Table SXXX: Genes deemed significantly up in ", table_name, " with", title_append, " according to ", according)
            up_titles[[table_name]] <- up_title
            down_title <- paste0("Table SXXX: Genes deemed significantly down in ", table_name, " with", title_append, " according to ", according)
            down_titles[[table_name]] <- down_title
        } ## End extracting significant genes for loop

        change_counts <- cbind(change_counts_up, change_counts_down)
        summary_title <- paste0("Counting the number of changed genes by contrast according to ", according, " with ", title_append)
        ## xls_result <- write_xls(data=change_counts, sheet="number_changed", file=sig_table,
        ##                         title=summary_title,
        ##                         overwrite_file=TRUE, newsheet=TRUE)

        ret[[according]] <- list(
            "ups" = trimmed_up,
            "downs" = trimmed_down,
            "counts" = change_counts,
            "up_titles" = up_titles,
            "down_titles" = down_titles,
            "counts_title" = summary_title,
            "ma_plots" = ma_plots)
        if (is.null(excel) | (excel == FALSE)) {
            message("Not printing excel sheets for the significant genes.")
        } else {
            message(paste0("Printing significant genes to the file: ", excel))
            xlsx_ret <- print_ups_downs(ret[[according]], wb=wb, excel=excel, according=according, summary_count=summary_count, csv=csv, ma=ma)
            ## wb <- xlsx_ret[["workbook"]]
        }
    } ## End list of according_to's

    sig_bar_plots <- NULL
    if (!is.null(excel) & excel != FALSE & isTRUE(sig_bar)) {
        ## This needs to be changed to get_sig_genes()
        sig_bar_plots <- significant_barplots(combined, fc_cutoffs=siglfc_cutoffs,
                                              p=p, z=z, p_type=p_type, fc_column=fc_column)
        plot_row <- 1
        plot_col <- 1
        message(paste0("Adding significance bar plots."))

        plot_row <- plot_row + nrow(change_counts) + 3
        ## I know it is silly to set the row in this very explicit fashion, but I want to make clear the fact that the table
        ## has a title, a set of headings, a length corresponding to the number of contrasts,  and then the new stuff should be added.

        ## Now add in a table summarizing the numbers in the plot.
        ## The information required to make this table is in sig_bar_plots[["ups"]][["limma"]] and sig_bar_plots[["downs"]][["limma"]]
        summarize_ups_downs <- function(ups, downs) {
            ## The ups and downs tables have 1 row for each contrast, 3 columns of numbers named 'a_up_inner', 'b_up_middle', 'c_up_outer'.
            ups <- ups[, -1]
            downs <- downs[, -1]
            ups[[1]] <- as.numeric(ups[[1]])
            ups[[2]] <- as.numeric(ups[[2]])
            ups[[3]] <- as.numeric(ups[[3]])
            ups[["up_sum"]] <- rowSums(ups)
            downs[[1]] <- as.numeric(downs[[1]])
            downs[[2]] <- as.numeric(downs[[2]])
            downs[[3]] <- as.numeric(downs[[3]])
            downs[["down_sum"]] <- rowSums(downs)
            summary_table <- as.data.frame(cbind(ups, downs))
            summary_table <- summary_table[, c(1, 2, 3, 5, 6, 7, 4, 8)]
            colnames(summary_table) <- c("up_0-2", "up_2-4", "up_gt_4",
                                         "down_0-2", "down_2-4", "down_gt_4",
                                         "sum_up", "sum_down")
            summary_table_idx <- rev(rownames(summary_table))
            summary_table <- summary_table[summary_table_idx, ]
            return(summary_table)
        }

        openxlsx::writeData(wb, "number_changed",
                            x="Significant limma genes.",
                            startRow=plot_row, startCol=plot_col)
        plot_row <- plot_row + 1
        tt <- try(print(sig_bar_plots[["limma"]]))
        tt <- try(openxlsx::insertPlot(wb, "number_changed", width=9, height=6,
                             startRow=plot_row, startCol=plot_col,
                             fileType="png", units="in"))

        summary_row <- plot_row
        summary_col <- plot_col + 11
        limma_summary <- summarize_ups_downs(sig_bar_plots[["ups"]][["limma"]], sig_bar_plots[["downs"]][["limma"]])
        limma_xls_summary <- write_xls(data=limma_summary, wb=wb, sheet="number_changed",
                                       rownames=TRUE, start_row=summary_row, start_col=summary_col)

        plot_row <- plot_row + 30
        openxlsx::writeData(wb, "number_changed",
                            x="Significant deseq genes.",
                            startRow=plot_row, startCol=plot_col)
        plot_row <- plot_row + 1
        tt <- try(print(sig_bar_plots[["deseq"]]))
        tt <- try(openxlsx::insertPlot(wb, "number_changed", width=9, height=6,
                                       startRow=plot_row, startCol=plot_col,
                                       fileType="png", units="in"))
        summary_row <- plot_row
        summary_col <- plot_col + 11
        deseq_summary <- summarize_ups_downs(sig_bar_plots[["ups"]][["deseq"]], sig_bar_plots[["downs"]][["deseq"]])
        deseq_xls_summary <- write_xls(data=deseq_summary, wb=wb, sheet="number_changed",
                                       rownames=TRUE, start_row=summary_row, start_col=summary_col)

        plot_row <- plot_row + 30
        openxlsx::writeData(wb, "number_changed",
                            x="Significant edger genes.",
                            startRow=plot_row, startCol=plot_col)
        plot_row <- plot_row + 1
        tt <- try(print(sig_bar_plots[["edger"]]))
        tt <- try(openxlsx::insertPlot(wb, "number_changed", width=9, height=6,
                                       startRow=plot_row, startCol=plot_col,
                                       fileType="png", units="in"))
        summary_row <- plot_row
        summary_col <- plot_col + 11
        edger_summary <- summarize_ups_downs(sig_bar_plots[["ups"]][["edger"]], sig_bar_plots[["downs"]][["edger"]])
        edger_xls_summary <- write_xls(data=edger_summary, wb=wb, sheet="number_changed",
                                       rownames=TRUE, start_row=summary_row, start_col=summary_col)

    } ## End if we want significance bar plots
    ret[["sig_bar_plots"]] <- sig_bar_plots

    if (!is.null(excel) & excel != FALSE) {
        excel_ret <- try(openxlsx::saveWorkbook(wb, excel, overwrite=TRUE))
    }

    return(ret)
}

#' Reprint the output from extract_significant_genes().
#'
#' I found myself needing to reprint these excel sheets because I
#' added some new information. This shortcuts that process for me.
#'
#' @param upsdowns  Output from extract_significant_genes().
#' @param wb  Workbook object to use for writing, or start a new one.
#' @param excel  Filename for writing the data.
#' @param csv  Write a csv instead/also?
#' @param according  Use limma, deseq, or edger for defining 'significant'.
#' @param summary_count  For spacing sequential tables one after another.
#' @param ma  Include ma plots?
#' @return Return from write_xls.
#' @seealso \code{\link{combine_de_tables}}
#' @export
print_ups_downs <- function(upsdowns, wb=NULL, excel="excel/significant_genes.xlsx", csv=NULL,
                            according="limma", summary_count=1, ma=FALSE) {
    xls_result <- NULL
    if (is.null(wb)) {
        wb <- openxlsx::createWorkbook(creator="hpgltools")
    }
    csv_basename <- NULL
    if (!is.null(csv)) {
        if (is.null(excel) | excel == FALSE) {
            csv_basename <- "excel/csv_export"
        } else {
            csv_basename <- excel
            csv_basename <- gsub(pattern="\\.xlsx", replacement="", x=csv_basename)
        }
    }
    ups <- upsdowns[["ups"]]
    downs <- upsdowns[["downs"]]
    up_titles <- upsdowns[["up_titles"]]
    down_titles <- upsdowns[["down_titles"]]
    summary <- upsdowns[["counts"]]
    summary_title <- upsdowns[["counts_title"]]
    ma_plots <- upsdowns[["ma_plots"]]
    table_count <- 0
    summary_count <- summary_count - 1
    num_tables <- length(names(ups))
    summary_start <- ((num_tables + 2) * summary_count) + 1
    xls_summary_result <- write_xls(wb, data=summary, start_col=1, start_row=summary_start, sheet="number_changed", title=summary_title)
    if (!is.null(csv)) {
        csv_filename <- paste0(csv_basename, "_num_changed.csv")
        write.csv(x=summary, file=csv_filename)
    }
    for (base_name in names(ups)) {
        table_count <- table_count + 1
        up_name <- paste0("up_", table_count, according, "_", base_name)
        down_name <- paste0("down_", table_count, according, "_", base_name)
        up_table <- ups[[table_count]]
        down_table <- downs[[table_count]]
        up_title <- up_titles[[table_count]]
        down_title <- down_titles[[table_count]]
        message(paste0(table_count, "/", num_tables, ": Writing excel data sheet ", up_name))
        xls_result <- write_xls(data=up_table, wb=wb, sheet=up_name, title=up_title)
        if (isTRUE(ma)) {
            ma_row <- 1
            ma_col <- xls_result[["end_col"]] + 1
            is_basic <- try(print(ma_plots[[base_name]]), silent=TRUE)
            ## The above will fail if this was a basic analysis, because I don't do ma plots on them.
            if (class(is_basic) != "try-error") {
                tt <- try(openxlsx::insertPlot(wb, up_name, width=6, height=6,
                                               startCol=ma_col, startRow=ma_row, fileType="png", units="in"))
            }
        }
        message(paste0(table_count, "/", num_tables, ": Writing excel data sheet ", down_name))
        xls_result <- write_xls(data=down_table, wb=wb, sheet=down_name, title=down_title)
        if (!is.null(csv)) {
            csv_filename <- paste0(csv_basename, "_", up_name, ".csv")
            write.csv(x=up_table, file=csv_filename)
            csv_filename <- paste0(csv_basename, "_", down_name, ".csv")
            write.csv(x=down_table, file=csv_filename)
        }
    } ## End for each name in ups
    return(xls_result)
}