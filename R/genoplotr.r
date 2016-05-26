
test_genoplotr <- function() {
    data(three_genes, package="genoPlotR")
    comparisons[[1]]$col <- genoPlotR::apply_color_scheme(c(0.6, 0.4, 0.5), "grey")
    names <- c("Huey", "Dewey", "Louie")
    names(dna_segs) <- names
    tree <- ade4::newick2phylog("(((Huey:4.2,Dewey:3.9):3.1,Louie:7.3):1);")
    mid_pos <- genoPlotR::middle(dna_segs[[1]])
    xlims <- list(c(Inf, -Inf), c(-Inf, Inf), c(1850, 2800))
    annot <- genoPlotR::annotation(x1=c(mid_pos[1], dna_segs[[1]]$end[2]),
                                   x2=c(NA, dna_segs[[1]]$end[3]),
                                   text=c(dna_segs[[1]]$name[1], "region1"),
                                   rot=c(30, 0), col=c("blue", "black"))
    genoPlotR::plot_gene_map(dna_segs=dna_segs, comparisons=comparisons,
                             annotations=annot, annotation_height=1.3,
                             tree=tree, tree_width=2,
                             xlims=xlims,
                             main="Comparison of Huey, Dewey and Louie")

    BH <- try(genoPlotR::read_dna_seg_from_file("NC_005956.gbk"))
    BQ <- try(genoPlotR::read_dna_seg_from_file("NC_005955.gbk"))
    BH_vs_BQ <- try(genoPlotR::read_comparison_from_blast("NC_005956_vs_NC_005955.blast"))
    xlims <- list(c(1,50000), c(1,50000))
    genoPlotR::plot_gene_map(dna_segs=list(BH, BQ),
                             comparisons=list(BH_vs_BQ),
                             xlims=xlims,
                             main="BH vs BQ, comparison of the first 50 kb",
                             gene_type="side_blocks",
                             dna_seg_scale=TRUE, scale=FALSE)

    grid::pushViewport(
        viewport(
            layout=grid::grid.layout(
                3, 1,
                heights=grid::unit(c(1,1.3,0.8), rep("null", 3))),
            name="overall_vp"))

    grid::pushViewport(grid::viewport(layout.pos.row=1, name="panelA"))
    genoPlotR::plot_gene_map(dna_segs=bbone$dna_segs, comparisons=bbone$comparisons,
                             dna_seg_scale=c(FALSE, FALSE, FALSE, TRUE),
                             scale=FALSE, main="A", main_pos="left", plot_new=FALSE)
    grid::upViewport()
    ## Panel B
    grid::pushViewport(grid::viewport(layout.pos.row=2, name="panelB"))
    genoPlotR::plot_gene_map(barto$dna_segs, barto$comparisons,
                             annotations=annots, tree=tree_barto, xlims=xlims,
                             limit_to_longest_dna_seg=FALSE, scale=FALSE,
                             dna_seg_scale=TRUE, main="B", main_pos="left",
                             annotation_height=0.6, annotation_cex=0.5,
                             plot_new=FALSE)
    grid::upViewport()
    ## Panel C
    grid::pushViewport(grid::viewport(layout.pos.row=3, name="panelC"))
    genoPlotR::plot_gene_map(chrY_subseg$dna_segs, chrY_subseg$comparison,
                             annotations=list(annot_homo, annot_pan),
                             dna_seg_scale=TRUE, scale=FALSE, main="C", main_pos="left",
                             plot_new=FALSE)
    grid::upViewport(0)
    grid_list <- grid::grid.ls(grob=TRUE, viewports=TRUE, print=FALSE)
    str(grid_list)
    grid::current.vpTree()
    grid::downViewport("panelA")
    for (i in 1:length(names)){
        new_label <- sub("_", ". ", names[[i]])
        grid.edit(paste("label", i, sep="."), label=new_label, gp=grid::gpar(fontface="italic"))
    }

    grid::grid.remove("label.2")
    grid::upViewport(0)
    grid::downViewport("panelB")
    grid::downViewport("dna_seg.3.2")
    grid::grid.rect(height = unit(2.2, "npc"), gp=grid::gpar(col="red", lwd=2, fill=0))
    grid::upViewport(0)
    dev.off()
}
