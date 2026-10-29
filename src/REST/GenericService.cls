/// REST business service that turns the JSON body of each HTTP request into a JVDoc.Document with a configured DocType
/// and sends it to its target, typically a JVDoc.ValidatingRouter. EnsLib.REST.GenericService would send an
/// EnsLib.HTTP.GenericMessage, which a VDoc routing engine cannot route (it has no DocType and no paths).
/// Responses: 400 with a JSON error for an empty or unparsable body; 202 when OneWay is set; otherwise the target's response
/// (a JVDoc.Document or stream container as its JSON or stream, an Ens.StringContainer or Ens.StringResponse as its text), or 204 when the target returns none.
/// Errors from the target are returned as the product's 500 response.
/// Author: QP
/// Version: 1.0
/// Last updated: 2026/10/28
Class JVDoc.REST.GenericService Extends EnsLib.REST.GenericService
{

/// DocType given to every incoming document, e.g. "PetStore:pet"; OnResolveJVDocType may choose another per request
Property DocType As %String(MAXLEN = 130);

Parameter SETTINGS = "DocType:Basic";

/// Builds the JVDoc document from the request body, sends it to TargetConfigName and turns the outcome into the HTTP response.<br>
/// <var>pRequestBody</var>: the HTTP body; its Attributes hold the HTTP headers and request details<br>
/// <var>pResponseBody</var> (output): the HTTP response body; its Attributes("ResponseCode") and Attributes("Content-Type") set the status and content type<br>
/// <var>pAction</var> (byref): passed by the adapter; not used<br>
/// Returns: $$$OK, or the error from sending to the target (answered by the product with 500)
Method OnProcessInput(pRequestBody As %CharacterStream, pResponseBody As %CharacterStream, ByRef pAction As %String) As %Status
{
    If $$$IsdefObject(%request) {
        Set %session.UseSessionCookie = 0
        Set %response.OutputSessionToken = 0
    }
    Set pResponseBody = $$$NULLOREF
    If '$IsObject(pRequestBody) || (pRequestBody.Size = 0) {
        Set pResponseBody = ..ErrorResponse("400 Bad Request", "Request body is empty")
        Quit $$$OK
    }
    Set tDocType = ..OnResolveJVDocType(pRequestBody)
    Set tDoc = ##class(JVDoc.Document).Create(pRequestBody, tDocType, .tSC)
    If $$$ISERR(tSC) {
        $$$LOGWARNING("Rejected request body: "_$System.Status.GetErrorText(tSC))
        Set pResponseBody = ..ErrorResponse("400 Bad Request", $System.Status.GetErrorText(tSC))
        Quit $$$OK
    }
    If ..OneWay {
        Set tSC = ..SendRequestAsync(..TargetConfigName, tDoc)
        If $$$ISOK(tSC) Set pResponseBody = ..Response("202 Accepted")
        Quit tSC
    }
    Set tSC = ..SendRequestSync(..TargetConfigName, tDoc, .tResponse)
    If $$$ISERR(tSC) Quit tSC
    Set pResponseBody = ..ResponseFrom($Get(tResponse))
    Quit $$$OK
}

/// Chooses the DocType of an incoming document; override it to pick the DocType from the URL or a header.<br>
/// <var>pRequestBody</var>: the HTTP body; pRequestBody.Attributes("URL") and the header attributes describe the request<br>
/// Returns: the DocType "Cat:Name"; the DocType setting by default
Method OnResolveJVDocType(pRequestBody As %CharacterStream) As %String
{
    Quit ..DocType
}

/// Turns the target's response into the HTTP response body.<br>
/// <var>pResponse</var>: the response message, or "" when the target returned none<br>
/// Returns: a response stream: JSON for a JVDoc.Document, the stream of an Ens.StreamContainer, the text of an Ens.StringContainer or Ens.StringResponse, empty with 204 otherwise
Method ResponseFrom(pResponse) As %GlobalCharacterStream [ Private ]
{
    If '$IsObject(pResponse) Quit ..Response("204 No Content")
    If pResponse.%Extends("JVDoc.Document") {
        Set tOut = ..Response("200 OK", "application/json")
        Do pResponse.GetObj().%ToJSON(tOut)
        Quit tOut
    }
    If pResponse.%Extends("Ens.StreamContainer") && $IsObject(pResponse.Stream) {
        Set tOut = ..Response("200 OK", "application/json")
        Do pResponse.Stream.Rewind()
        Do tOut.CopyFrom(pResponse.Stream)
        Quit tOut
    }
    If pResponse.%Extends("Ens.StringContainer") || pResponse.%Extends("Ens.StringResponse") {
        Set tOut = ..Response("200 OK", "text/plain")
        Do tOut.Write(pResponse.StringValue)
        Quit tOut
    }
    Quit ..Response("204 No Content")
}

/// Creates an empty response stream with a status and content type.<br>
/// <var>pCode</var>: HTTP status, e.g. "200 OK"<br>
/// <var>pContentType</var>: content type; "" leaves the adapter's default<br>
/// Returns: the stream
ClassMethod Response(pCode As %String, pContentType As %String = "") As %GlobalCharacterStream [ Private ]
{
    Set tOut = ##class(%GlobalCharacterStream).%New()
    Set tOut.Attributes("ResponseCode") = pCode
    If pContentType '= "" Set tOut.Attributes("Content-Type") = pContentType
    Quit tOut
}

/// Creates a JSON error response {"error": text}.<br>
/// <var>pCode</var>: HTTP status, e.g. "400 Bad Request"<br>
/// <var>pText</var>: the error text<br>
/// Returns: the stream
ClassMethod ErrorResponse(pCode As %String, pText As %String) As %GlobalCharacterStream [ Private ]
{
    Set tOut = ..Response(pCode, "application/json")
    Set tErr = {"error":(pText)}
    Do tErr.%ToJSON(tOut)
    Quit tOut
}

}
