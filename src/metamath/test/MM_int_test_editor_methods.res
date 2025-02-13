open MM_parser
open MM_context
open MM_proof_tree
open MM_proof_tree_dto
open MM_provers
open MM_wrk_editor
open MM_wrk_editor_substitution
open MM_wrk_settings
open MM_wrk_search_asrt
open MM_wrk_unify
open MM_statements_dto
open MM_wrk_editor_json
open MM_wrk_pre_ctx_data
open MM_int_test_utils
open Common

type rootStmtsToUse =
    | AllStmts
    | NoneStmts
    | SomeStmts(array<stmtId>)

let createEditorState = (
    ~mmFilePath:string, 
    ~stopBefore:option<string>=?, 
    ~stopAfter:option<string>=?, 
    ~editorState:option<string>=?,
    ~debug:option<bool>=?, 
    ()
) => {
    let parens = "( ) { } [ ]"
    let settings = {
        parens,
        asrtsToSkip: [],
        descrRegexToDisc: "",
        labelRegexToDisc: "^(ax-frege54c)|(.+OLD)|(.+ALT)$",
        descrRegexToDepr: "",
        labelRegexToDepr: "",
        discColor:"",
        deprColor:"",
        tranDeprColor:"",
        editStmtsByLeftClick:true,
        initStmtIsGoal: false,
        defaultStmtLabel: "qed",
        defaultStmtType: "",
        unifMetavarPrefix: "&",
        checkSyntax: true,
        stickGoalToBottom: true,
        autoMergeStmts: false,
        typeSettings: [ ],
        webSrcSettings: [ ],
        longClickEnabled: true,
        longClickDelayMs: 500,
        hideContextSelector: false,
        showVisByDefault:false,
        editorHistMaxLength:0,
        allowedFrms: {
            inSyntax: {
                useDisc:false,
                useDepr:true,
                useTranDepr:true,
            },
            inEssen: {
                useDisc:false,
                useDepr:true,
                useTranDepr:true,
            },
        },
        useDefaultTransforms:false,
        useCustomTransforms:false,
        customTransforms:"",
    }

    let mmFileText = Expln_utils_files.readStringFromFile(mmFilePath)
    let (ast, _) = parseMmFile(~mmFileContent=mmFileText, ~skipComments=true, ~skipProofs=true, ())
    let ctx = loadContext(
        ast, 
        ~stopBefore?, 
        ~stopAfter?, 
        ~descrRegexToDisc=settings.descrRegexToDisc->strToRegex->Belt_Result.getExn,
        ~labelRegexToDisc=settings.labelRegexToDisc->strToRegex->Belt_Result.getExn,
        ~descrRegexToDepr=settings.descrRegexToDepr->strToRegex->Belt_Result.getExn,
        ~labelRegexToDepr=settings.labelRegexToDepr->strToRegex->Belt_Result.getExn,
        ~debug?, 
        ()
    )
    while (ctx->getNestingLevel != 0) {
        ctx->closeChildContext
    }
    
    let st = createInitialEditorState(
        ~preCtxData=preCtxDataMake(~settings)->preCtxDataUpdate(~ctx=([],ctx), ()),
        ~stateLocStor=
            switch editorState {
                | None => None
                | Some(fileName) => {
                    readEditorStateFromJsonStr(
                        Expln_utils_files.readStringFromFile(
                            getTestDataDir() ++ "/" ++ fileName ++ ".json"
                        )
                    )->Belt.Result.mapWithDefault(None, state => Some(state))
                }
            }
    )
    st->updateEditorStateWithPostupdateActions(s=>s)
}

let addStmt = (
    st:editorState, 
    ~before:option<stmtId>=?,
    ~typ:option<userStmtType>=?, 
    ~isGoal:bool=false,
    ~label:option<string>=?, 
    ~jstf:option<string>=?, 
    ~stmt:string, 
    ()
):(editorState,stmtId) => {
    let st = switch before {
        | None => st
        | Some(beforeStmtId) => {
            let st = st->uncheckAllStmts
            st->toggleStmtChecked(beforeStmtId)
        }
    }
    let (st,stmtId) = st->addNewStmt
    let st = st->completeContEditMode(stmtId, stmt)
    let st = switch label {
        | Some(label) => st->completeLabelEditMode(stmtId, label)
        | None => st
    }
    let st = switch typ {
        | Some(typ) => st->completeTypEditMode(stmtId, typ, isGoal)
        | None => st
    }
    let st = switch jstf {
        | Some(jstf) => st->completeJstfEditMode(stmtId, jstf)
        | None => st
    }
    let st = st->uncheckAllStmts
    (st->updateEditorStateWithPostupdateActions(st => st), stmtId)
}

let duplicateStmt = (st, stmtId):(editorState,stmtId) => {
    let st = st->uncheckAllStmts
    let st = st->toggleStmtChecked(stmtId)
    let st = st->duplicateCheckedStmt(false)
    if (st.checkedStmtIds->Js.Array2.length != 1) {
        raise(MmException({msg:`duplicateStmt: st.checkedStmtIds->Js.Array2.length != 1`}))
    } else {
        let (newStmtId,_) = st.checkedStmtIds[0]
        let st = st->uncheckAllStmts
        (st->updateEditorStateWithPostupdateActions(st => st), newStmtId)
    }
}

let updateStmt = (
    st, 
    stmtId,
    ~label:option<string=>string>=?,
    ~typ:option<userStmtType>=?,
    ~content:option<string>=?,
    ~jstf:option<string>=?,
    ~contReplaceWhat:option<string>=?,
    ~contReplaceWith:option<string>=?,
    ()
):editorState => {
    let st = switch label {
        | None => st
        | Some(label) => {
            let oldLabel = (st->editorGetStmtById(stmtId)->Belt_Option.getExn).label
            switch st->renameStmt(stmtId, label(oldLabel)) {
                | Error(msg) => raise(MmException({msg:msg}))
                | Ok(st) => st
            }
        }
    }
    let st = st->updateStmt(stmtId, stmt => {
        let stmt = switch typ {
            | None => stmt
            | Some(typ) => {...stmt, typ}
        }
        let stmt = switch jstf {
            | None => stmt
            | Some(jstf) => {...stmt, jstfText:jstf}
        }
        let stmt = switch content {
            | Some(_) => stmt
            | None => {
                switch (contReplaceWhat, contReplaceWith) {
                    | (Some(contReplaceWhat), Some(contReplaceWith)) => {
                        {
                            ...stmt, 
                            cont: stmt.cont
                                    ->contToStr
                                    ->Js.String2.replace(contReplaceWhat, contReplaceWith)
                                    ->strToCont(_, ())
                        }
                    }
                    | _ => stmt
                }
            }
        }
        stmt
    })
    let st = switch content {
        | Some(content) => st->completeContEditMode(stmtId, content)
        | None => st
    }
    st->updateEditorStateWithPostupdateActions(st => st)
}

let addStmtsBySearch = (
    st,
    ~addBefore:option<stmtId>=?,
    ~filterLabel:option<string>=?, 
    ~filterTyp:option<string>=?, 
    ~filterPattern:option<string>=?, 
    ~chooseLabel:string,
    ()
):editorState => {
    let st = switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot addStmtsBySearch when wrkCtx is None.`}))
        | Some(wrkCtx) => {
            let st = st->uncheckAllStmts
            let st = switch addBefore {
                | None => st
                | Some(stmtId) => st->toggleStmtChecked(stmtId)
            }
            let searchResults = doSearchAssertions(
                ~wrkCtx,
                ~frms=st.frms,
                ~label=filterLabel->Belt_Option.getWithDefault(""),
                ~typ=st.preCtx->ctxSymToIntExn(filterTyp->Belt_Option.getWithDefault("|-")),
                ~pattern=st.preCtx->ctxStrToIntsExn(filterPattern->Belt_Option.getWithDefault("")),
                ()
            )
            let st = switch searchResults->Js_array2.find(res => res.stmts[res.stmts->Js_array2.length-1].label == chooseLabel) {
                | None => 
                    raise(MmException({
                        msg:`addStmtsBySearch: could not find ${chooseLabel}. ` 
                            ++ `Available: ${searchResults->Js_array2.map(res => res.stmts[res.stmts->Js_array2.length-1].label)->Js_array2.joinWith(", ")} `
                    }))
                | Some(searchResult) => st->addNewStatements(searchResult)
            }
            st->uncheckAllStmts
        }
    }
    st->updateEditorStateWithPostupdateActions(st => st)
}

let addNewStmts = (st:editorState, newStmts:stmtsDto, ~before:option<stmtId>=?, ()):editorState => {
    assertNoErrors(st)
    let st = switch before {
        | None => st
        | Some(beforeStmtId) => {
            let st = st->uncheckAllStmts
            st->toggleStmtChecked(beforeStmtId)
        }
    }
    let st = st->addNewStatements(newStmts)
    let st = st->uncheckAllStmts
    st->updateEditorStateWithPostupdateActions(st => st)
}

let getStmtId = (
    st:editorState, 
    ~predicate:option<userStmt=>bool>=?,
    ~contains:option<string>=?, 
    ~label:option<string>=?, 
    ()
) => {
    let predicate = switch predicate {
        | None => _ => true
        | Some(predicate) => predicate
    }
    let predicate = switch contains {
        | None => predicate
        | Some(contains) => stmt => predicate(stmt) && stmt.cont->contToStr->Js.String2.includes(contains)
    }
    let predicate = switch label {
        | None => predicate
        | Some(label) => stmt => predicate(stmt) && stmt.label == label
    }

    let found = st.stmts->Js_array2.filter(predicate)
    if (found->Js_array2.length != 1) {
        raise(MmException({msg:`getStmtId:  found.length = ${found->Js_array2.length->Belt_Int.toString}`}))
    } else {
        found[0].id
    }
}

let deleteStmts = (st:editorState, ids:array<stmtId> ) => {
    let st = st->uncheckAllStmts
    let st = ids->Js_array2.reduce(
        (st, id) => st->toggleStmtChecked(id),
        st
    )
    let st = st->deleteCheckedStmts
    st->updateEditorStateWithPostupdateActions(st => st)
}

let applySubstitution = (st, ~replaceWhat:string, ~replaceWith:string, ~useMatching:bool):editorState => {
    assertNoErrors(st)
    let st = switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot applySubstitution when wrkCtx is None.`}))
        | Some(wrkCtx) => {
            let wrkSubs = findPossibleSubs(
                st, 
                wrkCtx->ctxStrToIntsExn(replaceWhat),
                wrkCtx->ctxStrToIntsExn(replaceWith),
                useMatching
            )->Belt.Result.getExn->Js.Array2.filter(subs => subs.err->Belt_Option.isNone)
            if (wrkSubs->Js.Array2.length != 1) {
                raise(MmException({msg:`Unique substitution was expected in applySubstitution.`}))
            } else {
                st->applySubstitutionForEditor(wrkSubs[0])
            }
        }
    }
    st->updateEditorStateWithPostupdateActions(st => st)
}

let unifyAll = (st):editorState => {
    assertNoErrors(st)
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot unifyAll when wrkCtx is None.`}))
        | Some(wrkCtx) => {
            let rootStmts = st->getRootStmtsForUnification->Js.Array2.map(userStmtToRootStmt)
            let proofTree = unifyAll(
                ~parenCnt = st.parenCnt,
                ~frms = st.frms,
                ~allowedFrms = st.settings.allowedFrms,
                ~wrkCtx,
                ~rootStmts,
                ~syntaxTypes=st.syntaxTypes,
                ~exprsToSyntaxCheck=st->getAllExprsToSyntaxCheck(rootStmts),
                ()
            )
            let proofTreeDto = proofTree->proofTreeToDto(rootStmts->Js_array2.map(stmt=>stmt.expr))
            applyUnifyAllResults(st, proofTreeDto)
        }
    }
}

let filterRootStmts = (stmts:array<userStmt>, rootStmtsToUse:rootStmtsToUse):array<expr> => {
    let stmtsFiltered = switch rootStmtsToUse {
        | AllStmts => stmts
        | NoneStmts => []
        | SomeStmts(ids) => stmts->Js_array2.filter(stmt => ids->Js_array2.includes(stmt.id))
    }
    stmtsFiltered->Js_array2.map(stmt => userStmtToRootStmt(stmt).expr)
}

let unifyBottomUp = (
    st,
    ~stmtId:stmtId,
    ~args0:rootStmtsToUse=AllStmts,
    ~args1:rootStmtsToUse=NoneStmts,
    ~asrtLabel:option<string>=?,
    ~maxSearchDepth:int=4, 
    ~lengthRestrict:lengthRestrict=Less,
    ~allowNewDisjForExistingVars:bool=true,
    ~allowNewStmts:bool=true,
    ~allowNewVars:bool=true,
    ~useDisc: option<bool>=?,
    ~useDepr: option<bool>=?,
    ~useTranDepr: option<bool>=?,
    ~chooseLabel:option<string>=?,
    ~chooseResult:option<stmtsDto => bool>=?,
    ()
):(editorState, stmtsDto) => {
    assertNoErrors(st)
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot unifyBottomUp when wrkCtx is None.`}))
        | Some(wrkCtx) => {
            let st = st->uncheckAllStmts
            let st = st->toggleStmtChecked(stmtId)
            let rootUserStmts = st->getRootStmtsForUnification
            let rootStmts = rootUserStmts->Js_array2.map(userStmtToRootStmt)
            let proofTree = MM_provers.unifyAll(
                ~parenCnt = st.parenCnt,
                ~frms = st.frms,
                ~wrkCtx,
                ~rootStmts,
                ~bottomUpProverParams = {
                    asrtLabel,
                    maxSearchDepth,
                    lengthRestrict,
                    allowNewDisjForExistingVars,
                    allowNewStmts,
                    allowNewVars,
                    args0:filterRootStmts(rootUserStmts, args0),
                    args1:filterRootStmts(rootUserStmts, args1),
                    maxNumberOfBranches: None,
                },
                ~allowedFrms={
                    inSyntax: st.settings.allowedFrms.inSyntax,
                    inEssen: {
                        useDisc: useDisc->Belt_Option.getWithDefault(st.settings.allowedFrms.inEssen.useDisc),
                        useDepr: useDepr->Belt_Option.getWithDefault(st.settings.allowedFrms.inEssen.useDepr),
                        useTranDepr: useTranDepr->Belt_Option.getWithDefault(st.settings.allowedFrms.inEssen.useTranDepr),
                    }
                },
                //~onProgress = msg => Js.Console.log(msg),
                ()
            )
            let proofTreeDto = proofTree->proofTreeToDto(rootStmts->Js_array2.map(stmt=>stmt.expr))
            let rootExprToLabel = st.stmts->Js.Array2.map(userStmtToRootStmt)
                ->Js_array2.map(stmt => (stmt.expr,stmt.label))
                ->Belt_HashMap.fromArray(~id=module(ExprHash))
            let result = proofTreeDtoToNewStmtsDto(
                ~treeDto = proofTreeDto, 
                ~exprToProve=rootStmts[rootStmts->Js_array2.length-1].expr,
                ~ctx = wrkCtx,
                ~typeToPrefix = 
                    Belt_MapString.fromArray(
                        st.settings.typeSettings->Js_array2.map(ts => (ts.typ, ts.prefix))
                    ),
                ~rootExprToLabel,
                ~reservedLabels=st.stmts->Js_array2.map(stmt => stmt.label)
            )
            let result = switch chooseLabel {
                | None => result
                | Some(chooseLabel) => {
                    result->Js_array2.filter(newStmtsDto => {
                        let lastStmt = newStmtsDto.stmts[newStmtsDto.stmts->Js_array2.length - 1]
                        switch lastStmt.jstf {
                            | Some({label}) => label == chooseLabel
                            | _ => raise(MmException({msg:`Cannot get asrt label from newStmtsDto.`}))
                        }
                    })
                }
            }
            let result = switch chooseResult {
                | None => result
                | Some(chooseResult) => result->Js_array2.filter(chooseResult)
            }
            if (result->Js_array2.length != 1) {
                raise(MmException({msg:`Cannot find a bottom-up result by filters provided.`}))
            } else {
                (st, result[0])
            }
        }
    }
}

let removeAllJstf = (st:editorState):editorState => {
    let st = {...st, stmts: st.stmts->Js.Array2.map(stmt => {...stmt, jstfText:""})}
    st->updateEditorStateWithPostupdateActions(st => st)
}

let addDisj = (st:editorState, disj:string):editorState => {
    let disjLines = st.disjText->multilineTextToNonEmptyLines
    disjLines->Js_array2.push(disj)->ignore
    let st = st->completeDisjEditMode( disjLines->Js.Array2.joinWith("\n") )
    st->updateEditorStateWithPostupdateActions(st => st)
}

let removeDisj = (st:editorState, disj:string):editorState => {
    let disjLines = st.disjText->multilineTextToNonEmptyLines
    let st = st->completeDisjEditMode(
        disjLines->Js_array2.filter(line => line != disj)->Js.Array2.joinWith("\n")
    )
    st->updateEditorStateWithPostupdateActions(st => st)
}

let setDisj = (st:editorState, disj:string):editorState => {
    let st = st->completeDisjEditMode( disj )
    st->updateEditorStateWithPostupdateActions(st => st)
}

let setVars = (st:editorState, vars:string):editorState => {
    let st = st->completeVarsEditMode( vars )
    st->updateEditorStateWithPostupdateActions(st => st)
}

let mergeStmt = (st:editorState, stmtId):editorState => {
    let st = st->uncheckAllStmts
    let st = st->toggleStmtChecked(stmtId)
    switch st->findStmtsToMerge {
        | Error(msg) => raise(MmException({msg:msg}))
        | Ok((stmt1,stmt2)) => {
            let stmtIdToUse = if (stmt1.id == stmtId) {stmt1.id} else {stmt2.id}
            let stmtIdToRemove = if (stmt1.id == stmtId) {stmt2.id} else {stmt1.id}
            let st = switch st->mergeStmts(stmtIdToUse, stmtIdToRemove) {
                | Ok(st) => st->uncheckAllStmts
                | Error(msg) => raise(MmException({msg:msg}))
            }
            let st = st->uncheckAllStmts
            st->updateEditorStateWithPostupdateActions(st => st)
        }
    }
}