#Set the MIME types for the iPXE boot files, etc. 

#EFI loader files  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.efi';mimeType='application/octet-stream'}  
#BIOS boot loaders  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.com';mimeType='application/octet-stream'}  
#BIOS loaders without F12 key press  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.n12';mimeType='application/octet-stream'}  
#For the boot.sdi file  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.sdi';mimeType='application/octet-stream'}  
#For the boot.bcd boot configuration files  & BCD file (with no extension)
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.bcd';mimeType='application/octet-stream'}
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.';mimeType='application/octet-stream'}   
#For the winpe images itself (already added on newer/patched versions of Windows Server
#add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.wim';mimeType='application/octet-stream'}  
#for the iPXE BIOS loader files  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.pxe';mimeType='application/octet-stream'}  
#For the UNDIonly version of iPXE  
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.kpxe';mimeType='application/octet-stream'}  
#For the .iso file type
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.iso';mimeType='application/octet-stream'}  
#For the .img file type
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.img';mimeType='application/octet-stream'}  
#For the .ipxe file 
add-webconfigurationproperty //staticContent -name collection -value @{fileExtension='.ipxe';mimeType='text/plain'}
