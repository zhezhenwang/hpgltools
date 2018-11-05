#' Convert a potentially non-unique vector from kegg into a normalized data
#' frame.
#'
#' This function seeks to reformat data from KEGGREST into something which is
#' rather easier to use.
#'
#' This could probably benefit from a tidyr-ish revisitation.
#'
#' @param vector  Information from KEGGREST
#' @param final_colname  Column name for the new information
#' @param flatten Flatten nested data?
#' @return  A normalized data frame of gene IDs to whatever.
#' @author atb
kegg_vector_to_df <- function(vector, final_colname="first", flatten=TRUE) {
  final_df <- data.frame(stringsAsFactors=FALSE)
  if (isTRUE(flatten)) {
    sorted <- order(names(vector))
    sorted_vector <- vector[sorted]
    sorted_names <- names(sorted_vector)
    duplicated_names <- duplicated(sorted_names)
    unique_vector <- sorted_vector[!duplicated_names]
    unique_df <- as.data.frame(unique_vector, stringsAsFactors=FALSE)
    colnames(unique_df) <- final_colname
    ## Next line should not be needed with stringsAsFactors=FALSE
    ##unique_df[[final_colname]] <- as.character(unique_df[[final_colname]])
    duplicated_vector <- sorted_vector[duplicated_names]
    ## Now append the duplicated entries to the existing data frame.
    if (length(duplicated_vector) > 0) {
      for (c in 1:length(duplicated_vector)) {
        append_name <- names(duplicated_vector)[c]
        append_entry <- as.character(duplicated_vector[c])
        unique_df[append_name, final_colname] <- glue(
          "{unique_df[append_name, final_colname]}, {append_entry}")
      }
    }
    final_df <- unique_df
    rm(unique_df)
    final_df[["GID"]] <- rownames(final_df)
    colnames(final_df) <- c(final_colname, "GID")
  } else {
    final_df <- as.data.frame(vector, stringsAsFactors=FALSE)
    final_df[["GID"]] <- names(vector)
    colnames(final_df) <- c(final_colname, "GID")
    na_set <- is.na(final_df)
    final_df[na_set] <- ""
  }
  final_df[["GID"]] <- gsub(pattern="^.*:", replacement="", x=final_df[["GID"]], perl=TRUE)
  return(final_df)
}

#' Create a data frame of pathways to gene IDs from KEGGREST
#'
#' This seeks to take the peculiar format from KEGGREST for pathway<->genes and
#' make it easier to deal with.
#'
#' @param species  String to use to query KEGG abbreviation.
#' @param abbreviation  If you already know the abbreviation, use it.
#' @param flatten  Flatten nested tables?
#' @return  dataframe with rows of KEGG gene IDs and columns of NCBI gene IDs
#'   and KEGG paths.
#' @author atb
#' @export
load_kegg_annotations <- function(species="coli", abbreviation=NULL, flatten=TRUE) {
  chosen <- NULL
  if (!is.null(abbreviation)) {
    species <- NULL
  }
  if (is.null(abbreviation) & is.null(species)) {
    stop("This requires either a species or 3 letter kegg id.")
  } else if (!is.null(abbreviation)) {
    chosen <- abbreviation
  } else {
    ## Then the species was provided.
    abbreviation <- get_kegg_orgn(species)
    if (length(abbreviation) == 0) {
      stop("Unable to find a matching abbreviation for the search: ", species, ".")
    }
    message("The possible abbreviations are: ", toString(abbreviation), ".")
    message("Choosing the first one: ", abbreviation[[1]])
    chosen <- abbreviation[[1]]
  }

  ## Getting a list of genes is easy, as they are unique.
  genes_vector <- try(KEGGREST::keggConv("ncbi-geneid", chosen))
  if (class(genes_vector) == "try-error") {
    if (grepl(pattern="HTTP 400", x=genes_vector)) {
      warning("KEGGREST returned bad request.")
      return(data.frame())
    }
  }
  genes_df <- kegg_vector_to_df(genes_vector, final_colname="ncbi_geneid", flatten=flatten)

  prot_vector <- KEGGREST::keggConv("ncbi-proteinid", chosen)
  prot_df <- kegg_vector_to_df(prot_vector, final_colname="ncbi_proteinid", flatten=flatten)

  uniprot_vector <- KEGGREST::keggConv("uniprot", chosen)
  uniprot_df <- kegg_vector_to_df(uniprot_vector, final_colname="uniprotid", flatten=flatten)

  path_vector <- KEGGREST::keggLink("pathway", chosen)
  path_df <- kegg_vector_to_df(path_vector, final_colname="pathways", flatten=flatten)

  if (isTRUE(flatten)) {
    result <- merge(genes_df, prot_df, by="GID", all=TRUE)
    rownames(result) <- result[["ID"]]
    result <- merge(result, uniprot_df, by="GID", all=TRUE)
    rownames(result) <- result[["ID"]]
    result <- merge(result, path_df, by="GID", all=TRUE)
    rownames(result) <- result[["ID"]]
  } else {
    result <- merge(genes_df, prot_df, by="GID", all=TRUE)
    result <- merge(result, uniprot_df, by="GID", all=TRUE)
    result <- merge(result, path_df, by="GID", all=TRUE)
  }

  result[["ncbi_geneid"]] <- gsub(
    pattern="ncbi-geneid:", replacement="", x=result[["ncbi_geneid"]])
  result[["ncbi_proteinid"]] <- gsub(
    pattern="ncbi-proteinid:", replacement="", x=result[["ncbi_proteinid"]])
  result[["uniprotid"]] <- gsub(pattern="up:", replacement="", x=result[["uniprotid"]])
  result[["pathways"]] <- gsub(pattern="path:", replacement="", x=result[["pathways"]])
  result[["kegg_geneid"]] <- glue("{chosen}:{result[['GID']]}")
  ## Now we have a data frame of all genes <-> ncbi-ids, pathways
  result_nas <- is.na(result)
  result[result_nas] <- ""
  rownames(result) <- make.names(result[["GID"]], unique=TRUE)
  return(result)
}

#' Maps KEGG identifiers to ENSEMBL gene ids.
#'
#' Takes a list of KEGG gene identifiers and returns a list of ENSEMBL
#' ids corresponding to those genes.
#'
#' @param kegg_ids List of KEGG identifiers to be mapped.
#' @return Ensembl IDs as a character list.
#' @seealso \pkg{KEGGREST}
#'  \code{\link[KEGGREST]{keggGet}}
#' @examples
#' \dontrun{
#' ensembl_list <- kegg_to_ensembl("a")
#' }
#' @export
map_kegg_dbs <- function(kegg_ids) {
  ## query gene ids 10 at a time (max allowed)
  result <- data.frame()
  split_kegg <- split(kegg_ids, ceiling(seq_along(kegg_ids) / 3))
  count <- 0
  for (x in split_kegg) {
    x <- as.character(unlist(x))
    ## print(x)
    query <- KEGGREST::keggGet(x)
    for (d in 1:length(query)) {
      count <- count + 1
      item <- query[d]
      dblinks <- item[[1]][["DBLINKS"]]
      row_names <- gsub(pattern="^(.*): (.*)$", replacement="\\1", x=dblinks)
      row_values <- gsub(pattern="^(.*): (.*)$", replacement="\\2", x=dblinks)
      column <- as.data.frame(row_values)
      rownames(column) <- row_names
      colnames(column) <- kegg_ids[count]
      if (count == 1) {
        result <- column
      } else {
        result <- merge(result, column, by="row.names", all=TRUE)
        rownames(result) <- result[["Row.names"]]
        result <- result[, -1]
      }
    }
  }
  result <- t(result)
  return(result)
}

## EOF
