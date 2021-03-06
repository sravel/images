#####################################################################################################
#
# Copyright 2019 CIRAD-INRA
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/> or
# write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# You should have received a copy of the CeCILL-C license with this program.
#If not see <http://www.cecill.info/licences/Licence_CeCILL-C_V1-en.txt>
#
# Intellectual property belongs to CIRAD and South Green developpement plateform
# Version 0.1.0 written by Sebastien RAVEL, François BONNOT, Sajid ALI, FOURNIER Elisabeth
#####################################################################################################

## load packages
library(EBImage)
library(MASS)
library(lattice)
library(ParallelLogger)
library(shinyjs)
library(e1071) #only for svm (not implemented)

# To write in log file or show progress if not in parallel mode
writeLOG <- function(path = NULL, create = FALSE, message = NULL, detail = NULL, mode = NULL, value = NULL, progress = NULL) {
    # if not GUI mode write to log file
    if (!is.null(path)){
      if (create == TRUE) {
        # create log file
        logfilename <- base::normalizePath(paste0(path, "/log.txt"), winslash = "/")
        unlink(logfilename)# Clean up log file from the previous example
        ParallelLogger::clearLoggers()# Clean up the loggers from the previous example
        ParallelLogger::addDefaultFileLogger(logfilename)
      }
      ParallelLogger::logInfo(paste0(message, detail))
    }
    if (mode == "GUI"){
      progress$set(value = value, message = message, detail = detail)
    }
  }

#table2 <- function(x, y) {
#  ta <- as.data.frame.matrix(table(x, y, dnn = c("group", "predict")))
#  errorRate = paste0("Error rate: ", round((1 - sum(diag( ta)) / sum(ta)) * 100, 2), '%')
#  return(list("tableTrain" = ta, "errorRate" = errorRate))
#}

load_group <- function(g, pathTraining) {
  path_group <- paste(pathTraining, g, sep = '/')
  files_group <- list.files( path_group, full.names = TRUE, pattern = "\\.jpg$|\\.jpeg$|\\.PNG$|\\.tif$", include.dirs = FALSE, ignore.case = TRUE)
  sample <- lapply(files_group, EBImage::readImage)
  ## creation of the data frame of the sampled pixels
  li <- lapply(sample, function(im) {
    data.frame(
      group = g,
      red = as.numeric(EBImage::imageData(im)[, , 1]),
      green = as.numeric(EBImage::imageData(im)[, , 2]),
      blue = as.numeric(EBImage::imageData(im)[, , 3])
    )
  })
  do.call(rbind, li)
}

rgb2hsv2 <- function(rgb) {
  ## convert a data frame from rgb to hsv
  w <- match(c("red", "green", "blue"), names(rgb))
  hsv <- t(grDevices::rgb2hsv(t(rgb[w])))
  rgb[w] <- hsv
  names(rgb)[w] <- colnames(hsv)
  rgb
}

# function to test if folder pass contain sub-folder limb, background lesion
existDirTraining <- function(dirTraining) {
  list(
    dirlimb = dir.exists(paste(dirTraining, "/limb", sep = .Platform$file.sep)),
    dirBackground = dir.exists(paste(dirTraining, "/background", sep = .Platform$file.sep)),
    dirLesion = dir.exists(paste(dirTraining, "/lesion", sep = .Platform$file.sep))
  )
}

#' Compute and saves on disk the parameters of the training set
#'
#' Training input folder must include sub-folders:
#' \itemize{
#'   \item limb
#'   \item background
#'   \item lesion
#' }
#' This sub-folder can contain either image files or sub-folders containing different groups of image files
#' The function return the confusion matrix and error rate.
#'
#' @param pathTraining The path of the folder containing sampled images for training. This folder must contain at least 3 sub-folders with name 'background', 'limb' and 'lesion'.
#' @param method Method of discrimainant analysis: "lda" (default), "qda" or "svm"
#' @param transform Function for data transformation before analysis (e.g. sqrt)
#' @param colormodel Model of color for the analysis: "rgb" (default) or "hsv"
#' @param mode auto selection to switch between GUI or CMD mode Default:"CMD")'.
#'
#' @examples
#' pathTraining <- '../Exemple1/learning/' ## FOR all OS (Linux Mac Windows)
#' pathTraining <- '..\\Exemple1\\learning' ## FOR windows only
#' confusionMatrix <- training(pathTraining)
#' confusionMatrix <- training(pathTraining, transform=function(x) log1p(x),colormodel='rgb', method='svm')
#' confusionMatrix <- training(pathTraining, colormodel='hsv', method='lda')
#' confusionMatrix <- training(pathTraining, transform=function(x) (sin(pi*(x-0.5))+1)/2, method='qda')
#' confusionMatrix <- training(pathTraining, transform=function(x) asin(2*x-1)/pi+0.5)
#' confusionMatrix <- training(pathTraining, transform=log1p)

training <- function(pathTraining, method = "lda", transform = NULL, colormodel = "rgb", mode = "CMD") {

    # transforme to full path with slash for window or linux
    pathTraining <- base::normalizePath(pathTraining, winslash = "/")

    if (!is.null(mode) && mode == "GUI"){
        # add progress bar
        progress <- shiny::Progress$new(min=0, max=7)
        on.exit(progress$close())
      }

    writeLOG( path = pathTraining, create = TRUE, message = "Training run, please wait ", detail = "VERSION: 1.0", mode = mode, progress = progress)
    version <- "1.0"

    if (!(method %in% c("lda", "qda", "svm"))){
      stop(paste(method," is not valid value for method, please only use 'lda', 'qda' or 'svm' "), call. = FALSE)
    }
    if (!(colormodel %in% c("rgb", "hsv"))){
      stop(paste(colormodel," is not valid value for colormodel, please only use 'rgb' or 'hsv'"), call. = FALSE)
    }

    listdirTraining <- existDirTraining(pathTraining)
    # if all subfolder exist run analysis
    if (listdirTraining$dirlimb == FALSE || listdirTraining$dirBackground == FALSE || listdirTraining$dirLesion == FALSE) {
      errorMess <- paste0(
        "Error not find all sub-folders !!!!:\n",
        "\t-  limb: ", listdirTraining$dirlimb, "\n",
        "\t-  background: ", listdirTraining$dirBackground, "\n",
        "\t-  lesion: ", listdirTraining$dirLesion, "\n"
      )
      stop(errorMess, call. = FALSE)
    }

    ## search for sub-folders in pathTraining
    writeLOG(path = pathTraining, message = NULL, detail = paste0("Start training on folder: ",pathTraining, " 1/6"), mode = mode, value = 1, progress = progress)
    writeLOG(path = pathTraining, message = NULL, detail = "Load sub-folders 2/7", mode = mode, value = 2, progress = progress)
    dirs <- list.dirs(pathTraining, recursive = FALSE, full.names = FALSE)

    ## check the existence of the sub-folders passed in argument
    limbDir <- list.dirs(paste0(pathTraining, "/limb"), full.names = FALSE)[-1]
    if (length(limbDir) == 0) {
      limbDir = "limb"
    } else {
      limbDir <- paste0("limb/", limbDir)
    }

    lesionDir <-
      list.dirs(paste0(pathTraining, "/lesion"), full.names = FALSE)[-1]
    if (length(lesionDir) == 0) {
      lesionDir = "lesion"
    } else {
      lesionDir <- paste0("lesion/", lesionDir)
    }

    backgroundDir <-
      list.dirs(paste0(pathTraining, "/background"), full.names = FALSE)[-1]
    if (length(backgroundDir) == 0) {
      backgroundDir = "background"
    } else {
      backgroundDir <- paste0("background/", backgroundDir)
    }

    groups <- c(backgroundDir, limbDir, lesionDir)
    if (any(duplicated(groups)))
      stop("Error: duplicated group names.")
    nbGroups <- length(groups)
    classes <-
      rbind(
        data.frame(class = "background", subclass = backgroundDir),
        data.frame(class = "limb", subclass = limbDir),
        data.frame(class = "lesion", subclass = lesionDir)
      )

    ## constitution of the data.frame of the pixels of the samples
    writeLOG(path = pathTraining, message = NULL, detail = "Build dataframe with train data 3/7", mode = mode, value = 3, progress = progress)
    li <- lapply(groups, load_group, pathTraining = pathTraining)
    df2 <- do.call(rbind, li)
    if (colormodel == "hsv")
      df2 <- rgb2hsv2(df2)
    if (!is.null(transform))
      df2[2:4] <- lapply(df2[2:4], transform)

    ## split df2 into train and test for cross-validation
    type <- rep("train", nrow(df2))
    type[sample(1:length(type), length(type) / 2)] <- "test"
    df.train <- df2[type == "train", ]
    df.test <- df2[type == "test", ]

    dfTEST <<- df2

    ## discriminant analysis
    ## compute lda1 for graphic output (even if method is not "lda")
    writeLOG(path = pathTraining, message = NULL, detail = paste("Apply method '",method,"' to train set 4/7"), mode = mode, value = 4, progress = progress)
    lda1 <- MASS::lda(df2[2:4], df2$group, prior = rep(1, length(groups)) / length(groups))
    df4 <- cbind(df2, as.data.frame(as.matrix(df2[2:4]) %*% lda1$scaling))

    if (method == "lda") {
      lda2 <- MASS::lda(df.train[2:4], df.train$group, prior = rep(1, length(groups)) / length(groups))
    }
    else if (method == "qda") {
      lda1 <- MASS::qda(df2[2:4], df2$group, prior = rep(1, length(groups)) / length(groups))
      lda2 <- MASS::qda(df.train[2:4], df.train$group, prior = rep(1, length(groups)) / length(groups))
    }
    else if (method == "svm") {
      ## only if library e1071 is installed
      svm1 <- svm(group ~ red + green + blue, data = df2, kernel = "radial", gamma = 10, cost = 1.8)
      svm2 <- svm(group ~ red + green + blue, data = df.train, kernel = "radial", gamma = 10, cost = 1.8)
    }

    ## common name for the 3 output files, identique to the folder name
    basename <- utils::tail(strsplit(pathTraining, '/')[[1]], 1)

    ## save results in text file
    file.txt <- paste(pathTraining, paste0(basename, ".txt"), sep = '/') ## text output file
    transformTXT <- paste("'",transform,"'")
    if (is.null(transform)) transformTXT <- "NULL"
    base::sink(file.txt)
    cat("Version", version, '\n')
    cat(paste0("training(pathTraining = '",pathTraining,"', method = '",method,"', transform = ",transformTXT,", colormodel = '",colormodel,"')"), '\n')
    if (!is.null(transform)) {
      cat("transform:\n")
      print(transform)
    }
    cat("colormodel:", colormodel, '\n')
    cat("method:", method, '\n')
    print(table(df2$group))
    cat('\n')
    if (method == "lda" || method == "qda") {
      #prédiction sur l’échantillon test
      df.test$predict <- stats::predict(lda2, df.test[2:4])$class
      print(paste(method,"scaling"))
      print(lda1$scaling)
      train <- list(version = version,
          lda1 = lda1,
          classes = classes,
          transform = transform,
          colormodel = colormodel,
          method = method
        )
    }
    else if (method == "svm") {
      #prédiction sur l’échantillon test
      ## only if library e1071 is installed
      print(paste(method,"scaling"))
      df.test$predict <- stats::predict(svm2, df.test)
      print(svm1)
      train <- list(version = version,
          svm11 = svm1,
          classes = classes,
          transform = transform,
          colormodel = colormodel,
          method = method
        )
    }
    #matrice de confusion
    tableTrain <- table(df.test$group, df.test$predict)
    errorRate <- paste0("Error rate: ", round((1 - sum(diag( tableTrain)) / sum(tableTrain)) * 100, 2), '%')
    tableTrain <- as.data.frame.matrix(tableTrain)
    cat('\n')
    print(tableTrain)
    cat('\n')
    cat(errorRate)
    base::sink()

    df4 <- data.frame(df4, classes = do.call(rbind, strsplit(as.character(df4$group), '/', 1))) ## add classes column

    writeLOG(path = pathTraining, message = NULL, detail = "Write output files (csv,jpeg) 5/7", mode = mode, value = 5, progress = progress)
    ## graph of groups in the discriminant plane
    plotFileTraining1_2 <- base::normalizePath(paste0(pathTraining, "/", basename, "1_2.jpeg"), winslash = "/") ## output file jpeg
    plotFileTraining1_3 <- base::normalizePath(paste0(pathTraining, "/", basename, "1_3.jpeg"), winslash = "/") ## output file jpeg
    plotFileTraining2_3 <- base::normalizePath(paste0(pathTraining, "/", basename, "2_3.jpeg"), winslash = "/") ## output file jpeg

    # Save picture of Discriminent analysis
    grDevices::jpeg(plotFileTraining1_2, width = 800, height = 800, quality = 100, units = "px")
    if (nbGroups <= 3) {
      g <- plotLDGraph(df4, df4$LD1, "LD1", df4$LD2, "LD2", df4$group, df4$classes, backgroundDir, limbDir, lesionDir)
      print(g)
      grDevices::dev.off()
#      rv$plotALL <- FALSE
    } else{
      g <- plotLDGraph(df4, df4$LD1, "LD1", df4$LD2, "LD2", df4$group, df4$classes.1, backgroundDir, limbDir, lesionDir)
      print(g)
      grDevices::dev.off()
      # Save picture of Discriminent analysis
      grDevices::jpeg(plotFileTraining1_3, width = 800, height = 800, quality = 100, units = "px")
      g <- plotLDGraph(df4, df4$LD1, "LD1", df4$LD3, "LD3", df4$group, df4$classes.1, backgroundDir, limbDir, lesionDir)
      print(g)
      grDevices::dev.off()
      # Save picture of Discriminent analysis
      grDevices::jpeg( plotFileTraining2_3, width = 800, height = 800, quality = 100, units = "px")
      g <- plotLDGraph(df4, df4$LD2, "LD2", df4$LD3, "LD3", df4$group, df4$classes.1, backgroundDir, limbDir, lesionDir)
      print(g)
      grDevices::dev.off()
    }

    ## save results
    writeLOG(path = pathTraining, message = NULL, detail = "Save analysis into R file 6/7", mode = mode, value = 6, progress = progress)
    file.train <- base::normalizePath(paste0(pathTraining, "/", basename, ".RData"), winslash = "/")
    save(train, file = file.train)
    writeLOG(path = pathTraining, message = NULL, detail = "End of Training 7/7", mode = mode, value = 7, progress = progress)
    return(list("tableTrain" = tableTrain, "errorRate" = errorRate))
  }


plotLDGraph <- function(df4, x, xname, y, yname, group, class, backgroundDir, limbDir, lesionDir) {
  # Palette color for graph
  colBackPalette <- c("#0000FF","#74D0F1","#26C4EC","#0F9DE8","#1560BD","#0095B6","#00CCCB","#1034A6","#0ABAB5","#1E7FCB")
  colLimbPalette <- c("#32CD32","#9ACD32","#00FA9A","#008000","#ADFF2F","#6B8E23","#3CB371","#006400","#2E8B57","#00FF00")
  colLesionPalette <- c("#FF0000","#DB0073","#91283B","#B82010","#FF4901","#AE4A34","#FF0921","#BC2001","#FF5E4D","#E73E01")

  colBack <- colBackPalette[1:length(backgroundDir)]
  colLimb <- colLimbPalette[1:length(limbDir)]
  colLesion <- colLesionPalette[1:length(lesionDir)]

  g <- ggplot2::ggplot(data = df4, ggplot2::aes( x = x, y = y, colour = group, shape = class)
    ) +
    ggplot2::geom_point() +
    ggplot2::scale_color_manual(values = c(colBack, colLimb, colLesion)) +
    ggplot2::labs( x = xname, y = yname,
      title = "Graph of dicriminante analysis",
      caption = "Source: LeAFtool", colour = "Groups"
    ) +
    ggplot2::theme( legend.position = "right", panel.grid.major = ggplot2::element_blank(), panel.grid.minor = ggplot2::element_blank()
    ) +
   ggplot2::guides(
      colour = ggplot2::guide_legend(override.aes = list(shape = c(
        rep(16, length(backgroundDir)), rep(15, length(limbDir)), rep(17, length(lesionDir))
      ))), shape = FALSE, size = FALSE
    )
    return(g)
}
