/// Builds the JVDoc demo environment inside the IRIS container image; run once in %SYS by the Dockerfile.
/// Creates the TESTBED database and namespace with Interoperability, loads JVDoc and the demo classes,
/// creates the PetStore DocTypes from petstore.json, binds the pet search table, creates the /PetStore web application
/// for JVDoc.REST.GenericService and sets Demo.JVDoc.Production to start with the instance.
Class JVDocDemo.Installer
{

Parameter NAMESPACE = "TESTBED";

Parameter SOURCEDIR = "/opt/jvdoc";

/// Runs every step; the Dockerfile fails the build when it returns an error.<br>
/// Returns: $$$OK, or the first error
ClassMethod Run() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tNS = ..#NAMESPACE
        // Demo passwords stay as shipped (SYS) and do not have to be changed at first login
        Do ##class(Security.Users).UnExpireUserPasswords("*")

        Set tDir = ##class(%File).NormalizeDirectory($System.Util.ManagerDirectory()_$ZConvert(tNS, "L"))
        If '##class(Config.Databases).Exists(tNS) {
            Do ##class(%File).CreateDirectoryChain(tDir)
            $$$ThrowOnError(##class(SYS.Database).CreateDatabase(tDir))
            Set tDB("Directory") = tDir
            $$$ThrowOnError(##class(Config.Databases).Create(tNS, .tDB))
        }
        If '##class(Config.Namespaces).Exists(tNS) {
            Set tNSP("Globals") = tNS, tNSP("Routines") = tNS
            $$$ThrowOnError(##class(Config.Namespaces).Create(tNS, .tNSP))
        }
        $$$ThrowOnError(##class(%EnsembleMgr).EnableNamespace(tNS, 1))

        Do ..InNamespace(tNS)

        Set tApp("NameSpace") = tNS
        Set tApp("DispatchClass") = "JVDoc.REST.GenericService"
        Set tApp("Description") = "JVDoc PetStoreService REST endpoint: POST /PetStoreService/PetStore/<anything>"
        Set tApp("Enabled") = 1
        Set tApp("AutheEnabled") = 64
        // Unauthenticated demo endpoint; the application role gives UnknownUser access to TESTBED
        Set tApp("MatchRoles") = ":%All"
        If ##class(Security.Applications).Exists("/PetStoreService") {
            $$$ThrowOnError(##class(Security.Applications).Modify("/PetStoreService", .tApp))
        } Else {
            $$$ThrowOnError(##class(Security.Applications).Create("/PetStoreService", .tApp))
        }
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    Quit tSC
}

/// Loads and compiles the classes and creates the demo data in the given namespace.<br>
/// <var>pNS</var>: the demo namespace
ClassMethod InNamespace(pNS As %String) [ Private ]
{
    New $Namespace
    Set $Namespace = pNS
    Set tSrc = ..#SOURCEDIR
    $$$ThrowOnError($System.OBJ.LoadDir(tSrc_"/src", "ck", , 1))
    $$$ThrowOnError(##class(JVDoc.SchemaImport).FromBundleFile("PetStore", tSrc_"/src/Demo/petstore.json", "properties"))
    $$$ThrowOnError(##class(JVDoc.Schema).SetSearchTable("PetStore:pet", "Demo.JVDoc.SearchTablePet"))
    $$$ThrowOnError(##class(Ens.Director).SetAutoStart("Demo.JVDoc.Production"))
}

}
