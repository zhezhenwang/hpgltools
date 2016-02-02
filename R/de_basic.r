## Time-stamp: <Tue Feb  2 16:27:12 2016 Ashton Trey Belew (abelew@gmail.com)>

#' \code{basic_pairwise()}  Perform a pairwise comparison among conditions which takes
#' nothing into account.  It _only_ takes the conditions, a mean value/variance among
#' them, divides by condition, and returns the result.  No fancy nomalizations, no
#' statistical models, no nothing.  It should be the very worst method possible.
#' But, it should also provide a baseline to compare the other tools against, they should
#' all do better than this, always.
#'
#' @param input a count table by sample
#' @param conditions a data frame of samples and conditions
#'
#' @return I am not sure yet
#' @seealso \pkg{limma} \pkg{DESeq2} \pkg{edgeR}
#' @export
#' @examples
#' \dontrun{
#' stupid_de <- basic_pairwise(expt)
#' }
basic_pairwise <- function(input, design=NULL) {
    message("Starting basic pairwise comparison.")
    input_class <- class(input)[1]
    if (input_class == 'expt') {
        conditions <- input$conditions
        if (!is.null(input$transform)) {
            if (input$transform != "raw") {
                message("The counts were already log2, reverting to raw.")
                data <- input$normalized$normalized_counts$count_table
            } else {
                data <- Biobase::exprs(input$expressionset)
            }
        } else {
            data <- Biobase::exprs(input$expressionset)
        }
    } else {  ## Not an expt class, data frame or matrix
        data <- as.data.frame(input)
        conditions <- as.factor(design$condition)
    }
    types <- levels(conditions)
    num_conds <- length(types)
    ## These will be filled with num_conds columns and numRows(input) rows.
    median_table <- data.frame()
    variance_table <- data.frame()
    ## First use conditions to rbind a table of medians by condition.
    message("Basic step 1/3: Creating median and variance tables.")
    for (c in 1:num_conds) {
        condition_name <- types[c]
        columns <- which(conditions == condition_name)
        if (length(columns) == 1) {
            med <- data.frame(data[,columns])
            var <- as.data.frame(matrix(NA, ncol=1, nrow=nrow(med)))
        } else {
            med_input <- data[,columns]
            med <- data.frame(Biobase::rowMedians(as.matrix(med_input)))
            colnames(med) <- c(condition_name)
            var <- as.data.frame(matrixStats::rowVars(as.matrix(med_input)))
            colnames(var) <- c(condition_name)
        }
        if (c == 1) {
            median_table <- med
            variance_table <- var
        } else {
            median_table <- cbind(median_table, med)
            variance_table <- cbind(variance_table, var)
        }
    } ## end creation of median and variance tables.
    rownames(median_table) <- rownames(data)
    rownames(variance_table) <- rownames(data)
    ## We have tables of the median values by condition
    ## Now perform the pairwise comparisons
    comparisons <- data.frame()
    tvalues <- data.frame()
    pvalues <- data.frame()
    lenminus <- num_conds - 1
    num_done <- 0
    column_list <- c()
    message("Basic step 2/3: Performing comparisons.")
    num_comparisons <- sum(1:lenminus)
    for (c in 1:lenminus) {
        c_name <- types[c]
        nextc <- c + 1
        for (d in nextc:length(types)) {
            num_done <- num_done + 1
            d_name <- types[d]
            ## Actually, all the other tools do a log2 subtraction
            ## so I think I will too
            message(paste0("Basic step 2/3: ", num_done, "/", num_comparisons, ": Performing log2 subtraction: ", d_name, "_vs_", c_name))
            division <- data.frame(
                log2(median_table[, d] + 0.5) - log2(median_table[, c] + 0.5))
            comparison_name <- paste0(d_name, "_vs_", c_name)
            column_list <- append(column_list, comparison_name)
            colnames(division) <- comparison_name
            ## Lets see if I can make a dirty p-value
            xcols <- which(conditions == c_name)
            ycols <- which(conditions == d_name)
            xdata <- as.data.frame(data[, xcols])
            ydata <- as.data.frame(data[, ycols])
            t_data <- vector("list", nrow(xdata))
            p_data <- vector("list", nrow(xdata))
            for (j in 1:nrow(xdata)) {
                test_result <- try(t.test(xdata[j, ], ydata[j, ]), silent=TRUE)
                if (class(test_result) == 'htest') {
                    t_data[[j]] <- test_result[[1]]
                    p_data[[j]] <- test_result[[3]]
                } else {
                    t_data[[j]] <- 0
                    p_data[[j]] <- 1
                }
            } ## Done calculating cheapo p-values
            ##t_values[mapply(is.na, t_values)] <- 0
            ##p_values[mapply(is.na, p_values)] <- 1
            if (num_done == 1) {
                comparisons <- division
                tvalues <- t_data
                pvalues <- p_data
            } else {
                comparisons <- cbind(comparisons, division)
                tvalues <- cbind(tvalues, t_data)
                pvalues <- cbind(pvalues, p_data)
            }
        } ## End for each d
    }
    comparisons[is.na(comparisons)] <- 0
    tvalues[is.na(tvalues)] <- 0
    pvalues[is.na(pvalues)] <- 1
    rownames(comparisons) <- rownames(data)
    rownames(tvalues) <- rownames(data)
    rownames(pvalues) <- rownames(data)
    all_tables <- list()
    message("Basic step 3/3: Creating faux DE Tables.")
    for (e in 1:length(colnames(comparisons))) {
        colname <- colnames(comparisons)[[e]]
        fc_column <- comparisons[,e]
        t_column <- tvalues[,e]
        p_column <- pvalues[,e]
        fc_column[mapply(is.infinite, fc_column)] <- 0
        numer_denom <- strsplit(x=colname, split="_vs_")[[1]]
        numerator <- numer_denom[1]
        denominator <- numer_denom[2]
        fc_table <- data.frame(numerator_median=median_table[[numerator]],
                               denominator_median=median_table[[denominator]],
                               numerator_var=variance_table[[numerator]],
                               denominator_var=variance_table[[denominator]],
                               t=t(as.data.frame(t_column)),
                               p=t(as.data.frame(p_column)),
                               logFC=fc_column)
        all_tables[[e]] <- fc_table
    }
    message("Basic: Returning tables.")
    names(all_tables) <- colnames(comparisons)
    retlist <- list(
        input_data=data, conditions_table=table(conditions),
        conditions=conditions, all_pairwise=comparisons,
        all_tables=all_tables, medians=median_table,
        variances=variance_table)
    return(retlist)
}

## EOF
