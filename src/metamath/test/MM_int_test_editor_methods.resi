open MM_wrk_editor
open MM_statements_dto

type rootStmtsToUse =
    | AllStmts
    | NoneStmts
    | SomeStmts(array<stmtId>)

let createEditorState: (
    ~mmFilePath: string,
    ~stopBefore: string=?,
    ~stopAfter: string=?,
    ~editorState:string=?,
    ~debug: bool=?,
    unit,
) => editorState

let addStmt: (
    editorState,
    ~before:stmtId=?,
    ~typ: userStmtType=?,
    ~isGoal:bool=?,
    ~label: string=?,
    ~jstf:string=?, 
    ~stmt: string,
    unit,
) => (editorState, stmtId)

let duplicateStmt: (editorState, stmtId) => (editorState, stmtId)

let updateStmt: (
    editorState,
    stmtId,
    ~label: string=>string=?,
    ~typ: userStmtType=?,
    ~content: string=?,
    ~jstf:string=?,
    ~contReplaceWhat: string=?,
    ~contReplaceWith: string=?,
    unit,
) => editorState

let addStmtsBySearch: (
    editorState,
    ~addBefore: stmtId=?,
    ~filterLabel: string=?,
    ~filterTyp: string=?,
    ~filterPattern: string=?,
    ~chooseLabel: string,
    unit,
) => editorState

let addNewStmts: ( editorState, stmtsDto, ~before: stmtId=?, unit, ) => editorState

let getStmtId: (
    editorState, 
    ~predicate:userStmt=>bool=?,
    ~contains:string=?, 
    ~label:string=?,
    ()
) => stmtId

let applySubstitution: (
    editorState,
    ~replaceWhat: string,
    ~replaceWith: string,
    ~useMatching:bool,
) => editorState

let unifyAll: editorState => editorState

let unifyBottomUp: (
    editorState,
    ~stmtId:stmtId,
    ~args0:rootStmtsToUse=?,
    ~args1:rootStmtsToUse=?,
    ~asrtLabel: string=?,
    ~maxSearchDepth: int=?,
    ~lengthRestrict: MM_provers.lengthRestrict=?,
    ~allowNewDisjForExistingVars:bool=?,
    ~allowNewStmts:bool=?,
    ~allowNewVars: bool=?,
    ~useDisc: bool=?,
    ~useDepr: bool=?,
    ~useTranDepr: bool=?,
    ~chooseLabel: string=?,
    ~chooseResult: stmtsDto=>bool =?,
    (),
) => (editorState, stmtsDto)

let removeAllJstf: editorState => editorState
let addDisj: ( editorState, string, ) => editorState
let removeDisj: ( editorState, string ) => editorState
let setDisj: ( editorState, string ) => editorState
let setVars: ( editorState, string ) => editorState
let mergeStmt: ( editorState, stmtId ) => editorState
let deleteStmts: (editorState, array<stmtId> ) => editorState