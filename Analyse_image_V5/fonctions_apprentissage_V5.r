options(width=160)

## packages n?cessaires
library(EBImage)
library(lattice)
library(MASS)

library(ggplot2)

subDir <-function(dirs) {
  class <- strsplit(dirs, "/")[[1]][1]
  subclass <- strsplit(dirs, "/")[[1]][2]
  if(is.na(subclass)){subclass <- class }

  cat(paste("CLASS:",class,"\t\tSUBCLASS:",subclass,"\n", sep=" "))
  nameList <- data.frame(class=class,subclass=subclass)
  return(nameList)

}


## fonction de lecture des images d'un groupe ; retourne le data.frame des pixels
load.group <- function(g,path.sample) {
    path.group <- paste(path.sample,g,sep='/')
    print(path.group)
    files.group <- list.files(path.group,full.names=TRUE,recursive=TRUE)
    # print(files.group)




    sample <- lapply(files.group,readImage)
    ## constitution du data frame des pixels ?chantillonn?s
    li <- lapply(sample, function(im) {
        data.frame(group=g,red=as.numeric(imageData(im)[,,1]), green=as.numeric(imageData(im)[,,2]), blue=as.numeric(imageData(im)[,,3]))
    })
    do.call(rbind, li)
}

apprentissage <- function(path.sample,fond,limbe,lesion) {
    ## Recherche des sous-r?pertoires de path.sample
    dirs <- list.dirs(path.sample,full.names=FALSE)[-1] ## -1 pour supprimer le premier nom (toujouts vide)

    limbDir <- list.dirs(paste0(path.sample,"limb"),full.names=FALSE)[-1]
    if (length(limbDir)==0){limbDir = "limb"}
    else { limbDir <- paste0("limb/",limbDir)}

    lesionDir <- list.dirs(paste0(path.sample,"/lesion"),full.names=FALSE)[-1]
    if (length(lesionDir)==0){lesionDir = "lesion"}
    else { lesionDir <- paste0("lesion/",lesionDir)}

    backgroundDir <- list.dirs(paste0(path.sample,"/background"),full.names=FALSE)[-1]
    if (length(backgroundDir)==0){backgroundDir = "background"}
    else { backgroundDir <- paste0("background/",backgroundDir)}

    print(limbDir)
    print(lesionDir)
    print(backgroundDir)

    ## v?rification de l'existence des sous-r?pertoires pass?s en argument
    group <- c(backgroundDir,limbDir,lesionDir)
    nbGroups <- length(group)
    print(nbGroups)

    if (any(is.na(match(group,dirs)))) stop(paste("Repertoire(s) inexistant(s).",group,dirs,"\n"))

    ## constitution du data.frame des pixels des ?chantillons
    li <- lapply(group,load.group,path.sample)
    df2 <- do.call(rbind, li)

    ## analyse discriminante
    lda1 <- lda(df2[2:4], df2$group)

    ## nom commun aux 3 fichiers de sortie, identique au nom du r?prtoire
    filename <- tail(strsplit(path.sample,'/')[[1]],1)

    ## ?criture du fichier texte des r?sultats
    file.txt <- paste(path.sample,paste0(filename,".txt"),sep='/') ## fichier de sortie texte
    sink(file.txt)
    print(table(df2$group))
    print(lda1$scaling)
    df2$predict <- predict(lda1, df2[2:4])$class
    print(table(df2$group, df2$predict))
    sink()

    ## graphe des groupes dans le plan discriminant
    file.png <- paste(path.sample,paste0(filename,".png"),sep='/') ## fichier de sortie png
    df4 <- cbind(df2, as.data.frame(as.matrix(df2[2:4])%*%lda1$scaling))

    df4 <- data.frame(df4, classes=do.call(rbind, strsplit(as.character(df4$group),'/',1)))
#    View(df4)

    png(file.png,width=480*6,height=480*6,res=72*6)

#    print(xyplot(LD2~LD1, group=group, cex=0.8, alpha=1, pch=1, asp=1, auto.key=TRUE, data=df4))

              print(
                    ggplot( data = df4) +
                            geom_point(aes(x = LD1, y = LD2,  shape = df4$classes.1, color = df4$group, group=df4$classes.1, fill = NULL)) +
                            labs( x = "New x axis label", y = "New y axis label",
                                    title = "Add a title above the plot",
                                    caption="Source: ALAMA"
                                ) +
                            guides(fill=guide_legend("TITLE", ncol=3)) +
                            theme(  legend.position = "top",
                                    legend.key = element_rect(fill=NA),
                                    legend.title=element_blank(),
                                    panel.grid.major = element_blank(),
                                    panel.grid.minor = element_blank()
                                )+
#                                guides(shape = FALSE, size = FALSE)+
                                scale_colour_discrete(name  ="Groups",
                                    breaks=df4$classes.1,
                                    labels=df4$group) +
                                scale_shape_discrete(name  ="Groups",
                                   breaks=df4$group,
                                   labels=df4$group)
                            )


    dev.off()




    ## sauvegarde de l'analyse
    file.lda <- paste(path.sample,paste0(filename,".RData"),sep='/')
    save(lda1,file=file.lda)

    ## sauvegarde des classes
    file.classes <- paste(path.sample,paste0(filename,"_classes.txt"),sep='/')
    classes <- rbind(data.frame(class="background",subclass=backgroundDir),data.frame(class="limb",subclass=limbDir),data.frame(class="lesion",subclass=lesionDir))
    write.table(classes,file.classes,row.names=FALSE,quote=FALSE,sep='\t')
}

##apprentissage <- function(path.sample,fond,limbe,lesion) {
##    ## Les arguments pass?s dans "..." doivent ?tre (dans cet ordre) le nom (relatif) des sous-r?pertoires fond, limbe, l?sions
##    ## Recherche des sous-r?pertoires de path.sample
##    dirs <- list.dirs(path.sample,full.names=FALSE)[-1] ## -1 pour supprimer le premier nom (toujouts vide)
##
##    ## v?rification de l'existence des sous-r?pertoires pass?s en argument
##    group <- c(fond,limbe,lesion)
##    if (any(is.na(match(group,dirs)))) stop("R?pertoire(s) inexistant(s).")
##
##    ## constitution du data.frame des pixels des ?chantillons
##    li <- lapply(group,load.group,path.sample)
##    df2 <- do.call(rbind, li)
##
##    ## analyse discriminante
##    lda1 <- lda(df2[2:4], df2$group)
##
##    ## nom commun aux 3 fichiers de sortie, identique au nom du r?prtoire
##    filename <- tail(strsplit(path.sample,'/')[[1]],1)
##
##    ## ?criture du fichier texte des r?sultats
##    file.txt <- paste(path.sample,paste0(filename,".txt"),sep='/') ## fichier de sortie texte
##    sink(file.txt)
##    print(table(df2$group))
##    print(lda1$scaling)
##    df2$predict <- predict(lda1, df2[2:4])$class
##    print(table(df2$group, df2$predict))
##    sink()
##
##    ## graphe des groupes dans le plan discriminant
##    file.pdf <- paste(path.sample,paste0(filename,".pdf"),sep='/') ## fichier de sortie pdf
##    df4 <- cbind(df2, as.data.frame(as.matrix(df2[2:4])%*%lda1$scaling))
##    pdf(file.pdf)
##    print(xyplot(LD2~LD1, group=group, cex=0.8, alpha=1, pch=1, asp=1, auto.key=TRUE, data=df4))
##    dev.off()
##
##    ## sauvegarde de l'analyse
##    file.lda <- paste(path.sample,paste0(filename,".RData"),sep='/')
##    save(lda1,file=file.lda)
##
##    file.classes <- paste(path.sample,paste0(filename,"_classes.txt"),sep='/')
##    classes <- rbind(data.frame(class="background",subclass=fond),data.frame(class="limb",subclass=limbe),data.frame(class="lesion",subclass=lesion))
##    write.table(classes,file.classes,row.names=FALSE,quote=FALSE,sep='\t')
##}
##
## Fin de fichier