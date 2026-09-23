# Printer Deployment

# Overview

There is no native printer installation support in Intune at this time. This document will serve as a guide to deploying printers to Intune using a Win32 app. In this guide we will be creating a Win32app to deploy 2 BizHub printers to a set of test devices. The same process can be repeated for other printer models.

# Resources

[Application Deployment](https://umd-dit.atlassian.net/wiki/spaces/DMS/pages/45285381/Application+Deployment)

<https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool> 

# Creating the App Package

## Download Scripts

All of the files are provided below for you to download. Alternatively, you can copy and paste the content from the sources [on this page](https://umd-dit.atlassian.net/wiki/spaces/DMS/pages/69763156/Printer+Deployment+Scripts) as you work through the process.  

Unzip these files into a working folder on your local machine for this process. This working folder will be where we place all relevant files for this package. Create a new folder to make sure that there is nothing else that will get accidentally added to the package later.   


## Sourcing Drivers

The first thing we'll need to install our required printers are the drivers they depend on.

In this section we will be working through the installation of a Konica Minolta BizHub C360i and a Konica Minolta BizHub C458, discussing the nuances around selecting a driver and noting the properties required from within the .INF driver file.

1. Since we are installing Konica Minolta printers, to start we will go to their website to review the latest drivers available to us. In this case we will be downloading the latest PCL6 drivers.  

   
2. Now that the required drivers have been downloaded, extract them into the working folder.   

   
3. Find the .INF driver files within the extracted folders and open them up in Notepad.  

     
Here is an example of the C458 driver .inf file:

   When you open the .INF files you will notice that Manufacturers will almost always write drivers for a specific printer and then add a whole family of other printers within it, allowing them to avoid having to write and manage drivers for hundreds of printers individually. In our example above, we can see that the Konica Minolta C458 driver was written for the C759 and the Konica Minolta C360i driver was written for the C750i. **This does not matter.**  
4. Find the printers you want to install within the .INF files and note their Driver Names as written within. You may not see the exact model you are looking for, so just select a present model from the same family. You can usually find this with a quick google search. In our example, the C360i is listed in its .INF file and the C458 is not. So we'll grab the C360i's listed name "KONICA MINOLTA C360iSeriesPCL" and the name of the C458's closest family printer "KONICA MINOLTA C658SeriesPCL".
5. You should now have the Driver Names of the Printers you'd like to install and can proceed to the next section.  
**Driver Printer Names**

   `KONICA MINOLTA C360iSeriesPC`  
`KONICA MINOLTA C658SeriesPCL`

## Create a Printers.CSV File

1. Create a Printers.csv file by copying the table below and populating it with information specific to your deployment. *Under the new campus refresh policy-based network, please use the printer's DDNS hostname instead of its IP address. *

     
**Additional Info:**

   `Name = 'Name of the Printer once installed'`  
`DriverName = 'Exact driver names extracted in previous step'`  
`PortAddress = 'FQDN'`  
`Comment = 'Comment'`  
`Location = 'Location of Printer'`  
2. Save the printers.csv into the working folder where you saved the extracted drivers and proceed to the next section.  

## Modify Scripts to Install the Required Printers

In this section we will be completing an overview of the scripts and their functions. Generally you will only need to edit the "Detection.ps1" Script. 

1. Save all the PowerShell and Command Prompt scripts [from this page](https://umd-dit.atlassian.net/wiki/spaces/DMS/pages/69763156/Printer+Deployment+Scripts) into the working folder, making sure to name them correctly.
2. Your working directory should now look similar to this:  

   
3. Open the Detection.ps1 script and edit the $Printers array (between lines 5 and 8), making sure to include all values in the 'Name' column of your Printers.csv.
4. Save the Detection.ps1 and you are now ready to package the working folder into a Win32 App.

## Packaging the Win32 App

For this section we will be utilizing the Microsoft Win32 Content Prep Tool found here: <https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool>

Refer back to our [Win32 App Packaging](https://umd-dit.atlassian.net/wiki/display/DMS/App+Packaging#AppPackaging-Win32PackagingProcess) instructions for additional information.

1. Run a command prompt as administrator.
2. Run the IntuneWinAppUtil.exe from the open command prompt window.
3. When prompted, specify the Source Folder, Setup File and Output Folder. Choose N when asked to specify a catalog folder and then hit Enter.   
In this particular package, notice that the setup file is actually the install.cmd file that you created.   

   `Source Folder = 'The working folder directory highlighted above'`  
`Setup File = 'The install.cmd file'`  
`Output Folder = 'This is where the utility will output the .intunewin package'`  
`Catalog Folder = 'This is not needed. We can simply enter: N'`  
4. You should now see the created .intunewin package. Feel free to rename this.  

   
5. It is encouraged that you save the printer deployment folder that you created for later so that if adjustments are needed you will not have to re-create the entire package.   
Before packaging again, remove the existing .intunewin file from the folder.
6. Continue to the next section. 

# Deploying the App Package

Now that we have the .intunewin package, we can create a Win32 app in Intune to deploy the printers to a given group of devices.

1. Navigate to the Intune Portal and use the Apps Node to drill down into the [Windows Apps](https://endpoint.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsWindowsMenu/~/windowsApps) page.
2. Select "Add" and choose "Windows app (Win32)" as the App type.
3. Hit “Select app package file”.
4. In the File Explorer Window that presents itself, browse to the printer deployment folder and select the .intunewin we created earlier. Click OK.
5. Edit the highlighted information appropriately and hit next. Make sure that your application name is clear and specific to the set of printers that you are installing. This will become important as different groups in your department may require different printer deployments.  

   
6. Specify the Install and Uninstall commands as 'install.cmd' and 'uninstall.cmd', and leave the App Install behavior as 'System' to allow the printers to be installed for all users if you're planning to deploy this app to a device group.   
    - If you're planning to deploy the app to a user group and not a device group, you will need to switch the Install behavior to 'User'.
    - Note that if you plan to deploy to a user group, you will not be able to make the app 'Required' to force it's install in the 'Assignments' section of the App. You will only be able to make it 'Available', meaning that users will have to go to to the Company Portal app and install the Printer Deployment App manually
    - <https://learn.microsoft.com/en-us/mem/intune/apps/apps-deploy>
7. Hit next.
8. Select the following 'Requirements' and hit next:  

   
9. For the 'Detection Rules' select 'Use a custom detection script' and then select the 'Detection.ps1' from your local working directory as the 'Script file'. Leave both toggles at 'No' and then hit next.  

   
10. There are no 'Dependencies' or 'Supersedence' for this app deployment so you can hit next twice to skip to the 'Scope Tags' section.
11. Ensure that only your department tag is applied and hit "next".
12. On the assignments page, add the device or user group you'd like to deploy the app to to the 'Required' or 'Available' sections and hit next.  

    
13. **Review the 'Review + Create' page thoroughly **and then hit the 'Create' button to create your printer deployment app.  

# Testing

To test, simply log into a device that the app was set to deploy to and either wait or open the Company Portal app. You will then see a notification informing you that the printer deployment app is installing. 

Review the printer install log file at **c:\\windows\\temp\\printer\_install.log** and check your installed printers to confirm that that the deployment was successful.

If you see your deployed printers, feel free to print a test page. 
