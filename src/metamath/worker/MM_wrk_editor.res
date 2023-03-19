open MM_context
open MM_parser
open MM_proof_tree
open MM_proof_tree_dto
open MM_syntax_tree
open MM_wrk_settings
open MM_parenCounter
open MM_substitution
open MM_wrk_ctx_data
open MM_provers
open MM_statements_dto

let newLabelPrefix = ""

type stmtSym = {
    id: string,
    sym: string,
    color: option<string>,
}

type stmtCont =
    | Text(array<stmtSym>)
    | Tree(syntaxTreeNode)

let contIsEmpty = cont => {
    switch cont {
        | Text(arr) => arr->Js_array2.length == 0
        | Tree(syntaxTreeNode) => syntaxTreeIsEmpty(syntaxTreeNode)
    }
}

let contToArrStr = cont => {
    switch cont {
        | Text(arr) => arr->Js_array2.map(stmtSym => stmtSym.sym)
        | Tree(syntaxTreeNode) => syntaxTreeToSymbols(syntaxTreeNode)
    }
}

let contToStr = cont => {
    cont->contToArrStr->Js_array2.joinWith(" ")
}

let strToCont = (
    str:string,
    ~preCtxColors: option<Belt_HashMapString.t<string>>=?,
    ~wrkCtxColors: option<Belt_HashMapString.t<string>>=?,
    ()
) => {
    Text(
        getSpaceSeparatedValuesAsArray(str)->Js.Array2.mapi((sym,i) => {
            {
                id: i->Belt.Int.toString ++ sym,
                sym,
                color:
                    switch preCtxColors->Belt_Option.flatMap(map => map->Belt_HashMapString.get(sym)) {
                        | Some(color) => Some(color)
                        | None => {
                            switch wrkCtxColors->Belt_Option.flatMap(map => map->Belt_HashMapString.get(sym)) {
                                | Some(color) => Some(color)
                                | None => None
                            }
                        }
                    }
            }
        })
    )
}

type userStmtType = E | P

let userStmtTypeFromStr = str => {
    switch str {
        | "e" => E
        | "p" => P
        | _ => raise(MmException({msg:`Cannot convert '${str}' to userStmtType`}))
    }
}

let userStmtTypeToStr = typ => {
    switch typ {
        | E => "e"
        | P => "p"
    }
}

type stmtId = string

type proofStatus = Ready | Waiting | NoJstf | JstfIsIncorrect

type userStmt = {
    id: stmtId,

    label: string,
    labelEditMode: bool,
    typ: userStmtType,
    typEditMode: bool,
    cont: stmtCont,
    contEditMode: bool,
    
    jstfText: string,
    jstfEditMode: bool,

    stmtErr: option<string>,

    expr: option<expr>,
    jstf: option<jstf>,
    proof: option<(proofTreeDto, proofNodeDto)>,
    proofStatus: option<proofStatus>,
}

type editorState = {
    settingsV:int,
    settings:settings,
    typeColors: Belt_HashMapString.t<string>,

    preCtxV: int,
    preCtx: mmContext,
    frms: Belt_MapString.t<frmSubsData>,
    parenCnt: parenCnt,
    preCtxColors: Belt_HashMapString.t<string>,

    varsText: string,
    varsEditMode: bool,
    varsErr: option<string>,
    wrkCtxColors: Belt_HashMapString.t<string>,

    disjText: string,
    disjEditMode: bool,
    disjErr: option<string>,
    disj: Belt_MapInt.t<Belt_SetInt.t>,

    wrkCtx: option<mmContext>,

    nextStmtId: int,
    stmts: array<userStmt>,
    checkedStmtIds: array<stmtId>,

    unifyAllIsRequiredCnt: int
}

type wrkSubsErr =
    | CommonVar({var1:int, var2:int, commonVar:int})
    | TypeMismatch({var:int, subsExpr:expr, typeExpr:expr})

type wrkSubs = {
    newDisj: disjMutable,
    subs: Belt_MapInt.t<expr>,
    mutable err: option<wrkSubsErr>,
}

let createEmptyUserStmt = (id, typ, label):userStmt => {
    { 
        id, 
        label, labelEditMode:false, 
        typ, typEditMode:false, 
        cont:Text([]), contEditMode:true,
        jstfText:"", jstfEditMode:false,
        stmtErr: None,
        expr:None, jstf:None, proof:None, proofStatus:None,
    }
}

let userStmtToRootStmt = (stmt:userStmt):rootStmt => {
    {
        isHyp:stmt.typ == E,
        label:stmt.label,
        expr:
            switch stmt.expr {
                | None => raise(MmException({msg:`Expr must be set for a userStmt before converting to rootStmt.`}))
                | Some(expr) => expr
            },
        jstf: stmt.jstf,
    }
}

let editorGetStmtById = (st,id) => st.stmts->Js_array2.find(stmt => stmt.id == id)

let editorGetStmtByIdExn = (st:editorState,id:stmtId):userStmt => {
    switch editorGetStmtById(st,id) {
        | None => raise(MmException({msg:`editorGetStmtByIdExn: Cannot find a statement by statement id.`}))
        | Some(stmt) => stmt
    }
}

let getStmtIdx = (st:editorState,id:stmtId):int => {
    st.stmts->Js_array2.findIndex(stmt => stmt.id == id)
}

let updateStmt = (st:editorState,id,update):editorState => {
    {
        ...st,
        stmts: st.stmts->Js_array2.map(stmt => if stmt.id == id {update(stmt)} else {stmt})
    }
}

let isStmtChecked = (st,id) => {
    st.checkedStmtIds->Js.Array2.includes(id)
}

let toggleStmtChecked = (st,id) => {
    if (isStmtChecked(st,id)) {
        {
            ...st,
            checkedStmtIds: st.checkedStmtIds->Js_array2.filter(checkedId => checkedId != id)
        }
    } else {
        {
            ...st,
            checkedStmtIds: st.checkedStmtIds->Js_array2.concat([id])
        }
    }
}

let checkAllStmts = (st:editorState):editorState => {
    {
        ...st,
        checkedStmtIds: st.stmts->Js.Array2.map(stmt => stmt.id)
    }
}

let uncheckAllStmts = (st:editorState):editorState => {
    {
        ...st,
        checkedStmtIds: []
    }
}

let deleteCheckedStmts = (st:editorState):editorState => {
    {
        ...st,
        stmts: st.stmts->Js_array2.filter(stmt => !isStmtChecked(st,stmt.id)),
        checkedStmtIds: [],
    }
}

let deleteStmt = (st:editorState, id:stmtId):editorState => {
    {
        ...st,
        stmts: st.stmts->Js_array2.filter(stmt => stmt.id != id),
        checkedStmtIds: st.checkedStmtIds->Js_array2.filter(checkedId => checkedId != id),
    }
}

let canMoveCheckedStmts = (st:editorState, up):bool => {
    let len = st.stmts->Js_array2.length
    len != 0 && st.checkedStmtIds->Js_array2.length != 0 && (
        (up && !isStmtChecked(st,st.stmts[0].id)) || (!up && !isStmtChecked(st,st.stmts[len-1].id))
    )
}

let moveCheckedStmts = (st:editorState,up):editorState => {
    if (!canMoveCheckedStmts(st,up)) {
        st
    } else {
        let len = st.stmts->Js_array2.length
        let res = st.stmts->Js.Array2.copy
        if up {
            let maxI = len-2
            for i in 0 to maxI {
                if (!isStmtChecked(st,res[i].id) && isStmtChecked(st,res[i+1].id)) {
                    let tmp = res[i]
                    res[i] = res[i+1]
                    res[i+1] = tmp
                }
            }
        } else {
            for i in len-1 downto 1 {
                if (isStmtChecked(st,res[i-1].id) && !isStmtChecked(st,res[i].id)) {
                    let tmp = res[i]
                    res[i] = res[i-1]
                    res[i-1] = tmp
                }
            }
        }
        {
            ...st,
            stmts: res,
        }
    }
}

let getAllStmtsUpToChecked = (st):array<userStmt> => {
    let checkedAdded = ref(false)
    let res = []
    let i = ref(0)
    let stmtsLen = st.stmts->Js_array2.length
    while (i.contents < stmtsLen && !checkedAdded.contents) {
        let stmt = st.stmts[i.contents]
        res->Js.Array2.push(stmt)->ignore
        checkedAdded.contents = st.checkedStmtIds->Js.Array2.includes(stmt.id)
        i.contents = i.contents + 1
    }
    res
}

let getRootStmtsForUnification = (st):array<userStmt> => {
    st->getAllStmtsUpToChecked
}

let createNewLabel = (st:editorState, prefix:string):string => {
    let reservedLabels = Belt_HashSetString.fromArray(st.stmts->Js_array2.map(stmt=>stmt.label))
    switch textToVarDefs(st.varsText) {
        | Error(_) => ()
        | Ok(varDefs) => {
            varDefs->Js_array2.forEach(varDef => {
                reservedLabels->Belt_HashSetString.add(varDef[0])
            })
        }
    }

    let labelIsReserved = label => reservedLabels->Belt_HashSetString.has(label) || st.preCtx->isHyp(label)
    
    let cnt = ref(1)
    let newLabel = ref(prefix ++ cnt.contents->Belt_Int.toString)
    while (labelIsReserved(newLabel.contents)) {
        cnt.contents = cnt.contents + 1
        newLabel.contents = prefix ++ cnt.contents->Belt_Int.toString
    }
    newLabel.contents
}

let getTopmostSelectedStmt = (st):option<userStmt> => {
    if (st.checkedStmtIds->Js.Array2.length == 0) {
        None
    } else {
        st.stmts->Js_array2.find(stmt => isStmtChecked(st,stmt.id))
    }
}

let addNewStmt = (st:editorState):(editorState,stmtId) => {
    let newId = st.nextStmtId->Belt_Int.toString
    let newLabel = createNewLabel(st, newLabelPrefix)
    let idToAddBefore = getTopmostSelectedStmt(st)->Belt_Option.map(stmt => stmt.id)
    (
        {
            ...st,
            nextStmtId: st.nextStmtId+1,
            stmts: 
                switch idToAddBefore {
                    | Some(idToAddBefore) => {
                        st.stmts->Js_array2.map(stmt => {
                            if (stmt.id == idToAddBefore) {
                                [createEmptyUserStmt(newId,P,newLabel), stmt]
                            } else {
                                [stmt]
                            }
                        })->Belt_Array.concatMany
                    }
                    | None => st.stmts->Js_array2.concat([createEmptyUserStmt(newId, P, newLabel)])
                }
        },
        newId
    )
}

let addNewStmtAtIdx = (st:editorState, idx:int):(editorState,stmtId) => {
    let savedCheckedStmtIds = st.checkedStmtIds
    let st = st->uncheckAllStmts
    let st = if (0 <= idx && idx < st.stmts->Js_array2.length) {
        st->toggleStmtChecked(st.stmts[idx].id)
    } else {
        st
    }
    let (st,stmtId) = st->addNewStmt
    let st = {...st, checkedStmtIds:savedCheckedStmtIds}
    (st,stmtId)
}

let isSingleStmtChecked = st => st.checkedStmtIds->Js_array2.length == 1

let duplicateCheckedStmt = st => {
    if (!isSingleStmtChecked(st)) {
        st
    } else {
        let newId = st.nextStmtId->Belt_Int.toString
        let newLabel = createNewLabel(st, newLabelPrefix)
        let idToAddAfter = st.checkedStmtIds[0]
        {
            ...st,
            nextStmtId: st.nextStmtId+1,
            stmts: 
                st.stmts->Js_array2.map(stmt => {
                    if (stmt.id == idToAddAfter) {
                        [stmt, {...stmt, id:newId, label:newLabel, jstfText:""}]
                    } else {
                        [stmt]
                    }
                })->Belt_Array.concatMany,
            checkedStmtIds: [newId],
        }
    }
}

let canGoEditModeForStmt = (st:editorState,stmtId) => {
    !(st.stmts->Js_array2.some(stmt => 
        stmt.id == stmtId && (stmt.labelEditMode || stmt.typEditMode || stmt.contEditMode || stmt.jstfEditMode)
    ))
}

let setVarsEditMode = st => {
    {
        ...st,
        varsEditMode: true
    }
}

let setDisjEditMode = st => {
    {
        ...st,
        disjEditMode: true
    }
}

let completeDisjEditMode = (st, newDisjText) => {
    {
        ...st,
        disjText:newDisjText,
        disjEditMode: false
    }
}

let setLabelEditMode = (st:editorState, stmtId) => {
    if (canGoEditModeForStmt(st, stmtId)) {
        updateStmt(st, stmtId, stmt => {...stmt, labelEditMode:true})
    } else {
        st
    }
}

let completeLabelEditMode = (st, stmtId, newLabel):editorState => {
    updateStmt(st, stmtId, stmt => {
        if (newLabel->Js_string2.trim != "") {
            {
                ...stmt,
                label:newLabel,
                labelEditMode: false
            }
        } else {
            stmt
        }
    })
}

let setContEditMode = (st, stmtId) => {
    if (canGoEditModeForStmt(st, stmtId)) {
        updateStmt(st, stmtId, stmt => {...stmt, contEditMode:true})
    } else {
        st
    }
}

let completeContEditMode = (st, stmtId, newContText):editorState => {
    updateStmt(st, stmtId, stmt => {
        if (newContText->Js_string2.trim == "") {
            stmt
        } else {
            {
                ...stmt,
                cont:strToCont(newContText, ~preCtxColors=st.preCtxColors, ~wrkCtxColors=st.wrkCtxColors, ()),
                contEditMode: false
            }
        }
    })
}

let setTypEditMode = (st, stmtId) => {
    if (canGoEditModeForStmt(st, stmtId)) {
        updateStmt(st, stmtId, stmt => {...stmt, typEditMode:true})
    } else {
        st
    }
}

let completeTypEditMode = (st, stmtId, newTyp) => {
    updateStmt(st, stmtId, stmt => {
        {
            ...stmt,
            typ:newTyp,
            typEditMode: false
        }
    })
}

let setJstfEditMode = (st, stmtId) => {
    if (canGoEditModeForStmt(st, stmtId)) {
        updateStmt(st, stmtId, stmt => {...stmt, jstfEditMode:true})
    } else {
        st
    }
}

let completeJstfEditMode = (st, stmtId, newJstf) => {
    updateStmt(st, stmtId, stmt => {
        {
            ...stmt,
            jstfText:newJstf,
            jstfEditMode: false
        }
    })
}

let incUnifyAllIsRequiredCnt = st => {
    {
        ...st,
        unifyAllIsRequiredCnt: st.unifyAllIsRequiredCnt + 1
    }
}

let extractVarColorsFromVarsText = (varsText:string, typeColors:Belt_HashMapString.t<string>):Belt_HashMapString.t<string> => {
    let res = Belt_HashMapString.make(~hintSize=16)
    switch textToVarDefs(varsText) {
        | Error(_) => ()
        | Ok(varDefs) => {
            varDefs->Js_array2.forEach(varDef => {
                let varName = varDef[2]
                let typ = varDef[1]
                switch typeColors->Belt_HashMapString.get(typ) {
                    | None => ()
                    | Some(color) => res->Belt_HashMapString.set(varName, color)
                }
            })
        }
    }
    res
}

let recalcTypeColors = (st:editorState):editorState => {
    {
        ...st,
        typeColors: st.settings.typeSettings
            ->Js_array2.map(ts => (ts.typ, ts.color))
            ->Belt_HashMapString.fromArray
    }
}

let recalcPreCtxColors = (st:editorState):editorState => {
    let preCtxColors = Belt_HashMapString.make(~hintSize=100)
    st.preCtx->forEachHypothesisInDeclarationOrder(hyp => {
        if (hyp.typ == F) {
            switch st.preCtx->ctxIntToSym(hyp.expr[0]) {
                | None => ()
                | Some(typeStr) => {
                    switch st.typeColors->Belt_HashMapString.get(typeStr) {
                        | None => ()
                        | Some(color) => {
                            preCtxColors->Belt_HashMapString.set(
                                st.preCtx->ctxIntToSymExn(hyp.expr[1]),
                                color
                            )
                        }
                    }
                }
            }
        }
        None
    })->ignore
    {
        ...st,
        preCtxColors
    }
}

let recalcWrkCtxColors = (st:editorState):editorState => {
    {
        ...st,
        wrkCtxColors: extractVarColorsFromVarsText(st.varsText, st.typeColors),
    }
}

let updateColorsInAllStmts = st => {
    {
        ...st,
        stmts: st.stmts->Js_array2.map(stmt => {
            ...stmt,
            cont: stmt.cont->contToStr->strToCont(~preCtxColors=st.preCtxColors, ~wrkCtxColors=st.wrkCtxColors, ())
        })
    }
}

let setSettings = (st, settingsV, settings) => {
    let st = { 
        ...st, 
        settingsV, 
        settings,
    }
    let st = recalcTypeColors(st)
    let st = recalcPreCtxColors(st)
    let st = recalcWrkCtxColors(st)
    let st = updateColorsInAllStmts(st)
    st
}

let setPreCtx = (st, preCtxV, preCtx) => {
    let st = { 
        ...st, 
        preCtxV, 
        preCtx, 
        frms: prepareFrmSubsData(~ctx=preCtx, ()),
        parenCnt: parenCntMake(prepareParenInts(preCtx, st.settings.parens), ())
    }
    let st = recalcPreCtxColors(st)
    let st = recalcWrkCtxColors(st)
    let st = updateColorsInAllStmts(st)
    st
}

let completeVarsEditMode = (st, newVarsText) => {
    let st = {
        ...st,
        varsText:newVarsText,
        varsEditMode: false
    }
    let st = recalcWrkCtxColors(st)
    let st = updateColorsInAllStmts(st)
    st
}

let stableSortStmts = (st, comp: (userStmt,userStmt)=>int) => {
    let stmtsLen = st.stmts->Js.Array2.length
    if (stmtsLen < 2) {
        st
    } else {
        let newStmts = st.stmts->Js.Array2.copy
        let changed = ref(true)
        let e = ref(stmtsLen - 2)
        while (e.contents >= 0 && changed.contents) {
            changed.contents = false
            for i in 0 to e.contents {
                if (comp(newStmts[i], newStmts[i+1]) > 0) {
                    let tmp = newStmts[i]
                    newStmts[i] = newStmts[i+1]
                    newStmts[i+1] = tmp
                    changed.contents = true
                }
            }
            e.contents = e.contents - 1
        }
        {
            ...st,
            stmts: newStmts
        }
    }
}

let sortStmtsByType = st => {
    let stmtToInt = stmt => {
        switch stmt.typ {
            | E => 1
            | P => 2
        }
    }
    st->stableSortStmts((a,b) => stmtToInt(a) - stmtToInt(b))
}

let removeAllTempData = st => {
    {
        ...st,
        varsErr: None,
        disjErr: None,
        stmts: st.stmts->Js_array2.map(stmt => {
            {
                ...stmt, 
                stmtErr: None,
                expr: None, 
                jstf: None, 
                proof: None, 
                proofStatus: None
            }
        })
    }
}

let userStmtHasErrors = stmt => {
    stmt.stmtErr->Belt_Option.isSome
}

let editorStateHasErrors = st => {
    st.varsErr->Belt_Option.isSome 
        || st.disjErr->Belt_Option.isSome 
        || st.stmts->Js_array2.some(userStmtHasErrors)
}

let parseWrkCtxErr = (st:editorState, wrkCtxErr:wrkCtxErr):editorState => {
    let st = switch wrkCtxErr.varsErr {
        | None => st
        | Some(msg) => {
            {...st, varsErr:Some(msg)}
        }
    }
    let st = switch wrkCtxErr.disjErr {
        | None => st
        | Some(msg) => {
            {...st, disjErr:Some(msg)}
        }
    }
    st
}

let refreshWrkCtx = (st:editorState):editorState => {
    let wrkCtxRes = createWrkCtx(
        ~preCtx=st.preCtx,
        ~varsText=st.varsText,
        ~disjText=st.disjText,
    )
    let st = switch wrkCtxRes {
        | Error(wrkCtxErr) => parseWrkCtxErr(st, wrkCtxErr)
        | Ok(wrkCtx) => {
            let st = {...st, wrkCtx:Some(wrkCtx)}
            st
        }
    }
    st
}

let parseJstf = (jstfText:string):result<option<jstf>,string> => {
    let jstfText = jstfText->Js_string2.trim
    if (jstfText->Js_string2.length == 0) {
        Ok(None)
    } else {
        let argsAndAsrt = jstfText->Js_string2.split(":")
        if (argsAndAsrt->Js_array2.length != 2) {
            Error(`Cannot parse justification: '${jstfText}' [1].`)
        } else {
            Ok(Some({
                args: argsAndAsrt[0]->getSpaceSeparatedValuesAsArray,
                label: argsAndAsrt[1]->Js_string2.trim
            }))
        }
    }
}

let setStmtExpr = (stmt:userStmt,wrkCtx:mmContext):userStmt => {
    if (userStmtHasErrors(stmt)) {
        stmt
    } else {
        try {
            {
                ...stmt,
                expr: Some(wrkCtx->ctxSymsToIntsExn(stmt.cont->contToArrStr)),
            }
        } catch {
            | MmException({msg}) => {...stmt, stmtErr:Some(msg)}
        }
    }
}

let setStmtJstf = (stmt:userStmt):userStmt => {
    if (userStmtHasErrors(stmt) || stmt.typ == E) {
        stmt
    } else {
        switch parseJstf(stmt.jstfText) {
            | Error(msg) => {...stmt, stmtErr:Some(msg)}
            | Ok(jstf) => {...stmt, jstf}
        }
    }
}

let isLabelDefined = (label:string, wrkCtx:mmContext, definedUserLabels:Belt_HashSetString.t) => {
    definedUserLabels->Belt_HashSetString.has(label) || wrkCtx->isHyp(label)
}

let validateStmtJstf = (
    stmt:userStmt, 
    wrkCtx:mmContext, 
    definedUserLabels:Belt_HashSetString.t,
    asrtsToSkip: array<string>
):userStmt => {
    if (userStmtHasErrors(stmt)) {
        stmt
    } else {
        switch stmt.jstf {
            | None => stmt
            | Some({args,label}) => {
                switch args->Js_array2.find(ref => !isLabelDefined(ref,wrkCtx,definedUserLabels) ) {
                    | Some(jstfArgLabel) => {
                        {...stmt, stmtErr:Some(`The reference '${jstfArgLabel}' is not defined.`)}
                    }
                    | None => {
                        if (!(wrkCtx->isAsrt(label))) {
                            if (asrtsToSkip->Js_array2.includes(label)) {
                                {...stmt, stmtErr:Some(`The label '${label}' refers to a skipped assertion.`)}
                            } else {
                                {...stmt, stmtErr:Some(`The label '${label}' doesn't refer to any assertion.`)}
                            }
                        } else {
                            stmt
                        }
                    }
                }
            }
        }
    }
}

let validateStmtLabel = (stmt:userStmt, wrkCtx:mmContext, definedUserLabels:Belt_HashSetString.t):userStmt => {
    if (userStmtHasErrors(stmt)) {
        stmt
    } else {
        if (stmt.typ == E) {
            switch wrkCtx->getTokenType(stmt.label) {
                | Some(_) => {
                    {...stmt, stmtErr:Some(`Cannot reuse label '${stmt.label}' [1].`)}
                }
                | None => {
                    if (isLabelDefined(stmt.label,wrkCtx,definedUserLabels)) {
                        {...stmt, stmtErr:Some(`Cannot reuse label '${stmt.label}' [2].`)}
                    } else {
                        stmt
                    }
                }
            }
        } else {
            if (isLabelDefined(stmt.label,wrkCtx,definedUserLabels)) {
                {...stmt, stmtErr:Some(`Cannot reuse label '${stmt.label}' [3].`)}
            } else {
                stmt
            }
        }
    }
}

let validateStmtExpr = (
    stmt:userStmt, 
    wrkCtx:mmContext,
    definedUserExprs:Belt_HashMap.t<expr,string,ExprHash.identity>,
):userStmt => {
    if (userStmtHasErrors(stmt)) {
        stmt
    } else {
        switch stmt.expr {
            | None => raise(MmException({msg:`Cannot validateStmtExpr without expr.`}))
            | Some(expr) => {
                switch wrkCtx->getHypByExpr(expr) {
                    | Some(hyp) => {
                        {...stmt, stmtErr:Some(`This statement is the same as the previously defined` 
                            ++ ` hypothesis - '${hyp.label}'`)}
                    }
                    | _ => {
                        switch definedUserExprs->Belt_HashMap.get(expr) {
                            | Some(prevStmtLabel) => {
                                {...stmt, stmtErr:Some(`This statement is the same as the previous` 
                                    ++ ` one - '${prevStmtLabel}'`)}
                            }
                            | None => stmt
                        }
                    }
                }
            }
        }
    }
}

let prepareUserStmtsForUnification = (st:editorState):editorState => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot prepareUserStmtsForUnification without wrkCtx.`}))
        | Some(wrkCtx) => {
            let stmtsLen = st.stmts->Js_array2.length
            let definedUserLabels = Belt_HashSetString.make(~hintSize=stmtsLen)
            let definedUserExprs = Belt_HashMap.make(~hintSize=stmtsLen, ~id=module(ExprHash))
            let actions = [
                validateStmtLabel(_, wrkCtx, definedUserLabels),
                setStmtExpr(_, wrkCtx),
                validateStmtExpr(_, wrkCtx, definedUserExprs),
                setStmtJstf,
                validateStmtJstf(_, wrkCtx, definedUserLabels, st.settings.asrtsToSkip),
            ]
            st.stmts->Js_array2.reduce(
                (st,stmt) => {
                    if (editorStateHasErrors(st)) {
                        st
                    } else {
                        let stmt = actions->Js_array2.reduce(
                            (stmt,action) => {
                                if (userStmtHasErrors(stmt)) {
                                    stmt
                                } else {
                                    action(stmt)
                                }
                            },
                            stmt
                        )

                        definedUserLabels->Belt_HashSetString.add(stmt.label)
                        if (!userStmtHasErrors(stmt)) {
                            switch stmt.expr {
                                | None => raise(MmException({msg:`Expr must be set in prepareUserStmtsForUnification.`}))
                                | Some(expr) => definedUserExprs->Belt_HashMap.set(expr, stmt.label)
                            }
                        }
                        st->updateStmt(stmt.id, _ => stmt)
                    }
                },
                st
            )
        }
    }
}

let prepareEditorForUnification = st => {
    [
        removeAllTempData,
        sortStmtsByType,
        refreshWrkCtx,
        prepareUserStmtsForUnification,
    ]->Js.Array2.reduce(
        (st,act) => {
            if (editorStateHasErrors(st)) {
                st
            } else {
                act(st)
            }
        },
        st
    )
}

let getTheOnlySelectedStmt = (st):option<userStmt> => {
    if (st.checkedStmtIds->Js.Array2.length != 1) {
        None
    } else {
        getTopmostSelectedStmt(st)
    }
}

let createNewVars = (st:editorState, varTypes:array<int>):(editorState,array<int>) => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot create new variables without wrkCtx.`}))
        | Some(wrkCtx) => {
            let numOfVars = varTypes->Js_array2.length
            if (numOfVars == 0) {
                (st,[])
            } else {
                let typeToPrefix = Belt_MapString.fromArray(
                    st.settings.typeSettings->Js_array2.map(ts => (ts.typ, ts.prefix))
                )
                let newVarNames = generateNewVarNames(
                    ~ctx=wrkCtx,
                    ~types=varTypes, 
                    ~typeToPrefix,
                    ()
                )
                let newHypLabels = generateNewLabels(
                    ~ctx=wrkCtx,
                    ~prefix="var", 
                    ~amount=numOfVars,
                    ()
                )
                wrkCtx->applySingleStmt(Var({symbols:newVarNames}))
                let varTypeNames = wrkCtx->ctxIntsToSymsExn(varTypes)
                newHypLabels->Js.Array2.forEachi((label,i) => {
                    wrkCtx->applySingleStmt(Floating({label, expr:[varTypeNames[i], newVarNames[i]]}))
                })
                let newVarInts = wrkCtx->ctxSymsToIntsExn(newVarNames)
                let newVarsText = newHypLabels->Js.Array2.mapi((label,i) => {
                    `${label} ${varTypeNames[i]} ${newVarNames[i]}`
                })->Js_array2.joinWith("\n")
                let st = {
                    ...st,
                    varsText: [st.varsText, newVarsText]->Js.Array2.joinWith("\n")->Js.String2.trim
                }
                let st = recalcWrkCtxColors(st)
                ( st, newVarInts )
            }
        }
    }
}

let createNewDisj = (st:editorState, newDisj:disjMutable):editorState => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot create new disjoints without wrkCtx.`}))
        | Some(wrkCtx) => {
            let newDisjTextLines = []
            newDisj->disjForEachArr(varInts => {
                let varsStr = wrkCtx->ctxIntsToSymsExn(varInts)
                wrkCtx->applySingleStmt(Disj({vars:varsStr}))
                newDisjTextLines->Js.Array2.push(varsStr->Js.Array2.joinWith(","))->ignore
            })
            if (newDisjTextLines->Js.Array2.length == 0) {
                st
            } else {
                let newDisjText = newDisjTextLines->Js.Array2.joinWith("\n")
                {
                    ...st,
                    disjText: [st.disjText, newDisjText]->Js.Array2.joinWith("\n")->Js.String2.trim
                }
            }
        }
    }
}

let stmtsHaveSameExpr = ( stmt:userStmt, stmtDto:stmtDto ):bool => {
    switch stmt.expr {
        | None => raise(MmException({msg:`Cannot compare statements without expr.`}))
        | Some(expr) => expr->exprEq(stmtDto.expr)
    }
}

let getUserStmtByExpr = (st, expr):option<userStmt> => {
    st.stmts->Js_array2.find(stmt => {
        switch stmt.expr {
            | None => raise(MmException({msg:`Cannot getUserStmtByExpr without stmt.expr.`}))
            | Some(stmtExpr) => stmtExpr->exprEq(expr)
        }
    })
}

let insertStmt = (
    st:editorState, 
    ~expr:expr, 
    ~jstf:option<jstf>, 
    ~before:option<stmtId>,
    ~placeAtMaxIdxByDefault:bool,
):(editorState,string) => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot insertStmt without wrkCtx.`}))
        | Some(wrkCtx) => {
            switch wrkCtx->getHypByExpr(expr) {
                | Some(hyp) => (st,hyp.label)
                | None => {
                    let maxIdx = switch before {
                        | None => st.stmts->Js_array2.length
                        | Some(stmtId) => {
                            switch st.stmts->Js_array2.findIndex(stmt => stmt.id == stmtId) {
                                | -1 => st.stmts->Js_array2.length
                                | idx => idx
                            }
                        }
                    }
                    let minIdx = switch jstf {
                        | None => 0
                        | Some({args}) => {
                            let remainingLabels = Belt_HashSetString.fromArray(args)
                            let minIdx = st.stmts->Js_array2.reducei(
                                (minIdx,stmt,idx) => {
                                    if (remainingLabels->Belt_HashSetString.isEmpty) {
                                        minIdx
                                    } else {
                                        remainingLabels->Belt_HashSetString.remove(stmt.label)
                                        idx + 1
                                    }
                                },
                                0
                            )
                            if (maxIdx < minIdx) { maxIdx } else { minIdx }
                        }
                    }

                    let updateExistingStmt = (st,existingStmt):(editorState,string) => {
                        let st = switch jstf {
                            | None => st
                            | Some(jstf) => {
                                st->updateStmt(existingStmt.id, stmt => { ...stmt, jstfText: jstfToStr(jstf) })
                            }
                        }
                        (st, existingStmt.label)
                    }

                    let insertNewStmt = (st,existingStmt:option<userStmt>):(editorState,string) => {
                        let newIdx = switch existingStmt {
                            | None => if placeAtMaxIdxByDefault {maxIdx} else {minIdx}
                            | Some(existingStmt) => {
                                let newIdx = st->getStmtIdx(existingStmt.id) + 1
                                if (minIdx <= newIdx && newIdx <= maxIdx) { newIdx } else { minIdx }
                            }
                        }
                        let (st,newStmtId) = st->addNewStmtAtIdx(newIdx)
                        let st = st->updateStmt(newStmtId, stmt => {
                            {
                                ...stmt,
                                typ: P,
                                cont: strToCont( 
                                    wrkCtx->ctxIntsToStrExn(expr), 
                                    ~preCtxColors=st.preCtxColors, ~wrkCtxColors=st.wrkCtxColors, ()
                                ),
                                contEditMode: false,
                                jstfText: jstf->Belt_Option.mapWithDefault("", jstfToStr),
                            }
                        })
                        (st, (st->editorGetStmtByIdExn(newStmtId)).label)
                    }

                    let existingJstfEqNewJstf = existingJstf => {
                        switch jstf {
                            | Some(jstf) => jstfEq(existingJstf, jstf)
                            | _ => false
                        }
                    }

                    switch getUserStmtByExpr(st,expr) {
                        | None => insertNewStmt(st,None)
                        | Some(existingStmt) => {
                            if (existingStmt.typ == E) {
                                (st, existingStmt.label)
                            } else {
                                switch parseJstf(existingStmt.jstfText) {
                                    | Ok(None) => updateExistingStmt(st,existingStmt)
                                    | Ok(Some(existingJstf)) => {
                                        if (existingJstf->existingJstfEqNewJstf) {
                                            (st, existingStmt.label)
                                        } else {
                                            insertNewStmt(st,Some(existingStmt))
                                        }
                                    }
                                    | Error(_) => {
                                        insertNewStmt(st,Some(existingStmt))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

let replaceDtoVarsWithCtxVarsInExprs = (newStmts:stmtsDto, newStmtsVarToCtxVar:Belt_MutableMapInt.t<int>):stmtsDto => {
    {
        ...newStmts,
        stmts: newStmts.stmts->Js_array2.map(stmt => {
            {
                ...stmt,
                expr: stmt.expr->Js_array2.map(i => newStmtsVarToCtxVar->Belt_MutableMapInt.getWithDefault(i,i))
            }
        })
    }
}

let addNewStatements = (st:editorState, newStmts:stmtsDto):editorState => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot add new statements without wrkCtx.`}))
        | Some(wrkCtx) => {
            let (st, newCtxVarInts) = createNewVars(st,newStmts.newVarTypes)
            let newStmtsVarToCtxVar = Belt_MutableMapInt.make()
            newStmts.newVars->Js.Array2.forEachi((newStmtsVarInt,i) => {
                newStmtsVarToCtxVar->Belt_MutableMapInt.set(newStmtsVarInt, newCtxVarInts[i])
            })
            let newStmts = replaceDtoVarsWithCtxVarsInExprs(newStmts, newStmtsVarToCtxVar)

            let newCtxDisj = disjMake()
            newStmts.newDisj->disjForEach((n,m) => {
                newCtxDisj->disjAddPair(
                    newStmtsVarToCtxVar->Belt_MutableMapInt.getWithDefault(n,n), 
                    newStmtsVarToCtxVar->Belt_MutableMapInt.getWithDefault(m,m), 
                )
            })
            let st = createNewDisj(st, newCtxDisj)

            let checkedStmt = st->getTopmostSelectedStmt
            let newStmtsLabelToCtxLabel = Belt_MutableMapString.make()

            let replaceDtoLabelsWithCtxLabels = jstf => {
                {
                    ...jstf,
                    args: jstf.args->Js_array2.map(arg => 
                        newStmtsLabelToCtxLabel->Belt_MutableMapString.getWithDefault(arg,arg)
                    )
                }
            }

            let placeAtMinIdxByDefault = newStmts.stmts->Js_array2.some(stmtDto => {
                st.stmts->Js_array2.some(userStmt => stmtsHaveSameExpr(userStmt, stmtDto))
            })
            let stMut = ref(st)
            newStmts.stmts->Js_array2.forEach(stmtDto => {
                if (checkedStmt->Belt.Option.isSome && stmtsHaveSameExpr(checkedStmt->Belt.Option.getExn, stmtDto)) {
                    let checkedStmt = checkedStmt->Belt.Option.getExn
                    stMut.contents = updateStmt(stMut.contents, checkedStmt.id, stmtToUpdate => {
                        {
                            ...stmtToUpdate,
                            jstfText:
                                switch stmtDto.jstf {
                                    | None => stmtToUpdate.jstfText
                                    | Some(jstf) => jstf->replaceDtoLabelsWithCtxLabels->jstfToStr
                                }
                        }
                    })
                    newStmtsLabelToCtxLabel->Belt_MutableMapString.set(stmtDto.label,checkedStmt.label)
                } else {
                    let (st, ctxLabel) = stMut.contents->insertStmt(
                        ~expr=stmtDto.expr, 
                        ~jstf=stmtDto.jstf->Belt_Option.map(replaceDtoLabelsWithCtxLabels), 
                        ~before = checkedStmt->Belt_Option.map(stmt => stmt.id),
                        ~placeAtMaxIdxByDefault = !placeAtMinIdxByDefault
                    )
                    stMut.contents = st
                    newStmtsLabelToCtxLabel->Belt_MutableMapString.set(stmtDto.label,ctxLabel)
                }
            })
            stMut.contents
        }
    }
}

let verifyTypesForSubstitution = (~parenCnt, ~ctx, ~frms, ~wrkSubs):unit => {
    let varToExprArr = wrkSubs.subs->Belt_MapInt.toArray
    let typesToProve = varToExprArr->Js_array2.map(((var,expr)) => 
        [ctx->getTypeOfVarExn(var)]->Js.Array2.concat(expr)
    )
    let proofTree = proveFloatings(
        ~wrkCtx=ctx,
        ~frms,
        ~floatingsToProve=typesToProve,
        ~parenCnt,
        ()
    )
    varToExprArr->Js_array2.forEachi(((var,expr), i) =>
        if (wrkSubs.err->Belt_Option.isNone) {
            let typeExpr = typesToProve[i]
            if (proofTree->ptGetNode(typeExpr)->pnGetProof->Belt_Option.isNone) {
                wrkSubs.err = Some(TypeMismatch({ var, subsExpr:expr, typeExpr, }))
            }
        }
    )
}

let convertSubsToWrkSubs = (~subs, ~tmpFrame, ~ctx):wrkSubs => {
    let frameVarToCtxVar = frameVar => {
        switch tmpFrame.frameVarToSymb->Belt_Array.get(frameVar) {
            | None => raise(MmException({msg:`Cannot convert frameVar to ctxVar.`}))
            | Some(ctxSym) => ctx->ctxSymToIntExn(ctxSym)
        }
    }
    let res = Belt_Array.range(0,tmpFrame.numOfVars-1)
        ->Js.Array2.map(v => {
            (
                frameVarToCtxVar(v),
                applySubs(
                    ~frmExpr=[v],
                    ~subs,
                    ~createWorkVar = 
                        _ => raise(MmException({msg:`Work variables are not supported in convertSubsToWrkSubs().`}))
                )
            )
        })
        ->Belt_HashMapInt.fromArray
    let maxVar = ctx->getNumOfVars-1
    for v in 0 to maxVar {
        if (!(res->Belt_HashMapInt.has(v))) {
            res->Belt_HashMapInt.set(v, [v])
        }
    }
    {
        subs: res->Belt_HashMapInt.toArray->Belt_MapInt.fromArray,
        newDisj: disjMake(),
        err: None,
    }
}

let verifyDisjoints = (~wrkSubs:wrkSubs, ~disj:disjMutable):unit => {
    let varToSubVars = Belt_HashMapInt.make(~hintSize=wrkSubs.subs->Belt_MapInt.size)

    let getSubVars = var => {
        switch varToSubVars->Belt_HashMapInt.get(var) {
            | None => {
                varToSubVars->Belt_HashMapInt.set(
                    var, 
                    switch wrkSubs.subs->Belt_MapInt.get(var) {
                        | None => []
                        | Some(expr) => expr->Js_array2.filter(s => s >= 0)
                    }
                )
                varToSubVars->Belt_HashMapInt.get(var)->Belt.Option.getExn
            }
            | Some(arr) => arr
        }
    }

    disj->disjForEach((n,m) => {
        if (wrkSubs.err->Belt_Option.isNone) {
            getSubVars(n)->Js_array2.forEach(nv => {
                if (wrkSubs.err->Belt_Option.isNone) {
                    getSubVars(m)->Js_array2.forEach(mv => {
                        if (wrkSubs.err->Belt_Option.isNone) {
                            if (nv == mv) {
                                wrkSubs.err = Some(CommonVar({
                                    var1:n,
                                    var2:m,
                                    commonVar:nv
                                }))
                            }
                            if (wrkSubs.err->Belt_Option.isNone && !(disj->disjContains(nv,mv))) {
                                wrkSubs.newDisj->disjAddPair(nv,mv)
                            }
                        }
                    })
                }
            })
        }
    })
}

let findPossibleSubs = (st, frmExpr, expr):array<wrkSubs> => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot search for substitutions without wrkCtx.`}))
        | Some(wrkCtx) => {
            let axLabel = generateNewLabels(~ctx=wrkCtx, ~prefix="temp-ax-", ~amount=1, ())[0]
            let tmpFrame = createFrame(
                ~ctx=wrkCtx, ~label=axLabel, ~exprStr=wrkCtx->ctxIntsToSymsExn(frmExpr), ~proof=None,
                ~skipEssentials=true, ~skipFirstSymCheck=true, ()
            )
            let frm = prepareFrmSubsDataForFrame(tmpFrame)
            let disj = wrkCtx->getAllDisj
            let foundSubs = []
            iterateSubstitutions(
                ~frmExpr=tmpFrame.asrt,
                ~expr,
                ~frmConstParts = frm.frmConstParts[frm.numOfHypsE], 
                ~constParts = frm.constParts[frm.numOfHypsE], 
                ~varGroups = frm.varGroups[frm.numOfHypsE],
                ~subs = frm.subs,
                ~parenCnt=st.parenCnt,
                ~consumer = subs => {
                    let wrkSubs = convertSubsToWrkSubs(~subs, ~tmpFrame, ~ctx=wrkCtx)
                    verifyDisjoints(~wrkSubs, ~disj)
                    if (wrkSubs.err->Belt_Option.isNone) {
                        verifyTypesForSubstitution(~parenCnt=st.parenCnt, ~ctx=wrkCtx, ~frms=st.frms, ~wrkSubs)
                    }
                    foundSubs->Js_array2.push(wrkSubs)->ignore
                    Continue
                }
            )->ignore
            foundSubs
        }
    }
}

let applyWrkSubs = (expr, wrkSubs): expr => {
    let resultSize = ref(0)
    expr->Js_array2.forEach(s => {
        if (s < 0) {
            resultSize.contents = resultSize.contents + 1
        } else {
            switch wrkSubs.subs->Belt_MapInt.get(s) {
                | None => raise(MmException({msg:`Cannot find a substitution for ${s->Belt_Int.toString} in applyWrkSubs.`}))
                | Some(expr) => resultSize.contents = resultSize.contents + expr->Js_array2.length
            }
        }
    })
    let res = Expln_utils_common.createArray(resultSize.contents)
    let e = ref(0)
    let r = ref(0)
    while (r.contents < resultSize.contents) {
        let s = expr[e.contents]
        if (s < 0) {
            res[r.contents] = s
            r.contents = r.contents + 1
        } else {
            let subExpr = wrkSubs.subs->Belt_MapInt.getExn(s)
            let len = subExpr->Js_array2.length
            Expln_utils_common.copySubArray(~src=subExpr, ~srcFromIdx=0, ~dst=res, ~dstFromIdx=r.contents, ~len)
            r.contents = r.contents + len
        }
        e.contents = e.contents + 1
    }
    res
}

let applySubstitutionForStmt = (st:editorState, ctx:mmContext, stmt:userStmt, wrkSubs:wrkSubs):userStmt => {
    let expr = ctx->ctxSymsToIntsExn(stmt.cont->contToArrStr)
    let newExpr = applyWrkSubs(expr, wrkSubs)
    {
        ...stmt,
        cont: ctx->ctxIntsToStrExn(newExpr)->strToCont(~preCtxColors=st.preCtxColors, ~wrkCtxColors=st.wrkCtxColors, ())
    }
}

let applySubstitutionForEditor = (st, wrkSubs:wrkSubs):editorState => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot apply substitution without wrkCtx.`}))
        | Some(wrkCtx) => {
            let st = createNewDisj(st, wrkSubs.newDisj)
            {
                ...st,
                stmts: st.stmts->Js_array2.map(stmt => applySubstitutionForStmt(st, wrkCtx,stmt,wrkSubs))
            }
        }
    }
}

let removeUnusedVars = (st:editorState):editorState => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot remove unused variables without wrkCtx.`}))
        | Some(wrkCtx) => {
            let usedSymbols = st.stmts
                ->Expln_utils_common.arrFlatMap(stmt=>stmt.cont->contToArrStr)
                ->Belt_SetString.fromArray
            let unusedVars = wrkCtx->getLocalVars->Js_array2.filter(var => !(usedSymbols->Belt_SetString.has(var)))
            if (unusedVars->Js_array2.length == 0) {
                st
            } else {
                let unusedVarInts = wrkCtx->ctxSymsToIntsExn(unusedVars)
                let usedVarsStr = wrkCtx->getLocalHyps
                    ->Js_array2.filter(hyp => hyp.typ == F && !(unusedVarInts->Js_array2.includes(hyp.expr[1])))
                    ->Js_array2.map(hyp => 
                        `${hyp.label} ${wrkCtx->ctxIntToSymExn(hyp.expr[0])} ${wrkCtx->ctxIntToSymExn(hyp.expr[1])}`
                    )
                    ->Js_array2.joinWith("\n")
                let st = completeVarsEditMode(st, usedVarsStr)
                let newDisj = disjMake()
                wrkCtx->getAllDisj->disjForEach((n,m) => {
                    if (!(unusedVarInts->Js_array2.includes(n)) && !(unusedVarInts->Js_array2.includes(m))) {
                        newDisj->disjAddPair(n,m)
                    }
                })
                let newDisjStrArr = []
                newDisj->disjForEachArr(varInts => {
                    newDisjStrArr->Js.Array2.push(wrkCtx->ctxIntsToSymsExn(varInts)->Js_array2.joinWith(","))->ignore
                })
                let st = completeDisjEditMode(st, newDisjStrArr->Js.Array2.joinWith("\n"))
                st
            }
        }
    }
}

let srcToJstf = (wrkCtx, proofTree:proofTreeDto, exprSrc:exprSrcDto, exprToUserStmt):option<jstf> => {
    switch exprSrc {
        | Assertion({args, label}) => {
            switch wrkCtx->getFrame(label) {
                | None => raise(MmException({msg:`Cannot find an assertion '${label}' in srcToJstf.`}))
                | Some(frame) => {
                    let argLabels = []
                    let argLabelsValid = ref(true)
                    frame.hyps->Js_array2.forEachi((hyp,i) => {
                        if (hyp.typ == E && argLabelsValid.contents) {
                            switch args->Belt_Array.get(i) {
                                | None => raise(MmException({msg:`Too few arguments for '${label}' in srcToJstf.`}))
                                | Some(nodeIdx) => {
                                    switch exprToUserStmt->Belt_HashMap.get(proofTree.nodes[nodeIdx].expr) {
                                        | None => argLabelsValid.contents = false //todo: return a meaningful error from here
                                        | Some(userStmt) => argLabels->Js_array2.push(userStmt.label)->ignore
                                    }
                                }
                            }
                        }
                    })
                    if (argLabelsValid.contents) {
                        Some({ args: argLabels, label })
                    } else {
                        None
                    }
                }
            }
        }
        | _ => None
    }
}

let userStmtSetJstfTextAndProof = (stmt, wrkCtx, proofTree:proofTreeDto, proofNode:proofNodeDto, exprToUserStmt):userStmt => {
    switch proofNode.proof {
        | None => stmt
        | Some(proofSrc) => {
            switch srcToJstf(wrkCtx, proofTree, proofSrc, exprToUserStmt) {
                | None => stmt
                | Some(jstfFromProof) => {
                    switch stmt.jstf {
                        | None => {
                            {
                                ...stmt,
                                jstfText: jstfToStr(jstfFromProof),
                                proof: Some((proofTree, proofNode)),
                            }
                        }
                        | Some(existingJstf) => {
                            if (jstfFromProof->jstfEq(existingJstf)) {
                                {
                                    ...stmt,
                                    proof: Some((proofTree, proofNode)),
                                }
                            } else {
                                stmt
                            }
                        }
                    }
                }
            }
        }
    }
}

let userStmtSetProofStatus = (stmt, wrkCtx, proofTree:proofTreeDto, proofNode:proofNodeDto, exprToUserStmt):userStmt => {
    let srcEqJstf = (src, jstf) => {
        switch srcToJstf(wrkCtx, proofTree, src, exprToUserStmt) {
            | None => false
            | Some(jstfFromSrc) => jstf->jstfEq(jstfFromSrc)
        }
    }

    switch stmt.proof {
        | Some(_) => {...stmt, proofStatus:Some(Ready)}
        | None => {
            switch stmt.jstf {
                | None => {...stmt, proofStatus:Some(NoJstf)}
                | Some(jstf) => {
                    switch proofNode.parents->Js.Array2.find(srcEqJstf(_, jstf)) {
                        | Some(_) => {...stmt, proofStatus:Some(Waiting)}
                        | None => {...stmt, proofStatus:Some(JstfIsIncorrect)}
                    }
                }
            }
        }
    }
}

let applyUnifyAllResults = (st,proofTreeDto) => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot applyUnifyAllResults without wrkCtx.`}))
        | Some(wrkCtx) => {
            let exprToNode = proofTreeDto.nodes
                ->Js_array2.map(node => (node.expr,node))
                ->Belt_HashMap.fromArray(~id=module(ExprHash))
            let exprToUserStmt = st.stmts
                                    ->Js_array2.map(stmt => {
                                        switch stmt.expr {
                                            | None => 
                                                raise(MmException({
                                                    msg:`Cannot applyUnifyAllResults without stmt.expr [1].`
                                                }))
                                            | Some(expr) => (expr, stmt)
                                        }
                                    })
                                    ->Belt_HashMap.fromArray(~id=module(ExprHash))
            st.stmts->Js_array2.reduce(
                (st,stmt) => {
                    let stmt = {...stmt, proof:None, proofStatus: None}
                    if (stmt.typ == P) {
                        st->updateStmt(stmt.id, stmt => {
                            switch stmt.expr {
                                | None => 
                                    raise(MmException({ msg:`Cannot applyUnifyAllResults without stmt.expr [2].`}))
                                | Some(expr) => {
                                    switch exprToNode->Belt_HashMap.get(expr) {
                                        | None => stmt
                                        | Some(node) => {
                                            let stmt = userStmtSetJstfTextAndProof(stmt,wrkCtx,proofTreeDto,node,exprToUserStmt)
                                            let stmt = userStmtSetProofStatus(stmt,wrkCtx,proofTreeDto,node,exprToUserStmt)
                                            stmt
                                        }
                                    }
                                }
                            }
                        })
                    } else {
                        st
                    }
                },
                st
            )
        }
    }
}

let updateEditorStateWithPostupdateActions = (st, update:editorState=>editorState) => {
    let st = update(st)
    let st = prepareEditorForUnification(st)
    if (st.wrkCtx->Belt_Option.isSome) {
        let st = removeUnusedVars(st)
        let st = prepareEditorForUnification(st)
        st
    } else {
        st
    }
}

let splitIntoChunks = (str, chunkMaxSize): array<string> => {
    let len = str->Js_string2.length
    if (len <= chunkMaxSize) {
        [str]
    } else {
        let res = []
        let numberOfChunks = Js.Math.ceil_int(len->Belt_Int.toFloat /. chunkMaxSize->Belt_Int.toFloat)
        for i in 1 to numberOfChunks {
            let begin = (i-1)*chunkMaxSize
            res->Js_array2.push(str->Js_string2.substrAtMost(~from=begin, ~length=chunkMaxSize))->ignore
        }
        res
    }
}

let proofToText = (ctx:mmContext,stmt:userStmt,proof:proof):string => {
    switch proof {
        | Compressed({labels, compressedProofBlock}) => {
            let blk = splitIntoChunks(compressedProofBlock, 50)->Js_array2.joinWith(" ")
            let asrt = `${stmt.label} $p ${stmt.cont->contToStr} $= ( ${labels->Js_array2.joinWith(" ")} ) ${blk} $.`
            let localVars = ctx->getLocalVars
            let localDisj = ctx->getLocalDisj
            let localHyps = ctx->getLocalHyps
            let blockIsRequired = localHyps->Js.Array2.length > 0 || !(localDisj->disjIsEmpty)
            let result = []
            if (blockIsRequired) {
                result->Js.Array2.push("${")->ignore
            }
            if (localVars->Js.Array2.length > 0) {
                result->Js.Array2.push("$v " ++ localVars->Js.Array2.joinWith(" ") ++ " $.")->ignore
            }
            localDisj->disjForEachArr(vars => {
                result->Js.Array2.push("$d " ++ ctx->ctxIntsToStrExn(vars) ++ " $.")->ignore
            })
            localHyps->Js.Array2.forEach(hyp => {
                let hypTypStr = if (hyp.typ == F) {
                    " $f "
                } else {
                    " $e "
                }
                result->Js.Array2.push(hyp.label ++ hypTypStr ++ ctx->ctxIntsToStrExn(hyp.expr) ++ " $.")->ignore
            })
            result->Js.Array2.push(asrt)->ignore
            if (blockIsRequired) {
                result->Js.Array2.push("$}")->ignore
            }
            result->Js.Array2.joinWith("\r\n")
        }
        | _ => "Error: only compressed proofs are supported."
    }
}

let generateCompressedProof = (st, stmtId):option<string> => {
    switch st.wrkCtx {
        | None => None
        | Some(wrkCtx) => {
            switch st.stmts->Js.Array2.find(stmt => stmt.id == stmtId) {
                | None => None
                | Some(stmt) => {
                    switch stmt.proof {
                        | None => None
                        | Some((proofTreeDto,proofNode)) => {
                            let proofTable = createProofTable(proofTreeDto,proofNode)
                            let proof = MM_proof_table.createProof(wrkCtx, proofTable, proofTable->Js_array2.length-1)
                            Some(proofToText(wrkCtx,stmt,proof))
                        }
                    }
                }
            }
        }
    }
}

let replaceRef = (st,~replaceWhat,~replaceWith):result<editorState,string> => {
    st.stmts->Js_array2.reduce(
        (res,stmt) => {
            switch res {
                | Error(_) => res
                | Ok(st) => {
                    switch parseJstf(stmt.jstfText) {
                        | Error(_) => Error(`Cannot parse justification '${stmt.jstfText}' ` 
                                                ++ `for the statement '${stmt.label}'`)
                        | Ok(None) => Ok(st)
                        | Ok(Some(jstf)) => {
                            if (jstf.args->Js.Array2.includes(replaceWhat)) {
                                let newJstf = {
                                    ...jstf,
                                    args: jstf.args
                                        ->Js_array2.map(ref => if (ref == replaceWhat) {replaceWith} else {ref})
                                }
                                Ok(
                                    st->updateStmt(stmt.id, stmt => {
                                        {
                                            ...stmt,
                                            jstfText: jstfToStr(newJstf)
                                        }
                                    })
                                )
                            } else {
                                Ok(st)
                            }
                        }
                    }
                }
            }
        },
        Ok(st)
    )
}

let mergeStmts = (st:editorState,id1:string,id2:string):result<editorState,string> => {
    switch st->editorGetStmtById(id1) {
        | None => Error(`Cannot find a statement with id = '${id1}'`)
        | Some(stmt1) => {
            switch st->editorGetStmtById(id2) {
                | None => Error(`Cannot find a statement with id = '${id2}'`)
                | Some(stmt2) => {
                    if (stmt1.cont->contToStr != stmt2.cont->contToStr) {
                        Error(`Statements to merge must have identical expressions.`)
                    } else {
                        switch replaceRef(st, ~replaceWhat=stmt2.label, ~replaceWith=stmt1.label) {
                            | Error(msg) => Error(msg)
                            | Ok(st) => {
                                let st = st->deleteStmt(id2)
                                Ok(st)
                            }
                        }
                    }
                }
            }
        }
    }
}

let symbolsNotAllowedInLabelRegex = %re("/[\s:]+/g")
let removeSymbolsNotAllowedInLabel = str => str->Js_string2.replaceByRe(symbolsNotAllowedInLabelRegex, "")

let renameStmt = (st:editorState, stmtId:string, newLabel:string):result<editorState,string> => {
    let newLabel = newLabel->removeSymbolsNotAllowedInLabel
    if (newLabel == "") {
        Error(`label must not be empty.`)
    } else {
        switch st.stmts->Js_array2.find(stmt => stmt.id != stmtId && stmt.label == newLabel) {
            | Some(_) => Error(`label '${newLabel}' is used by another statement.`)
            | None => {
                switch st->editorGetStmtById(stmtId) {
                    | None => Ok(st)
                    | Some(stmt) => {
                        if (stmt.label == newLabel) {
                            Ok(st)
                        } else {
                            switch replaceRef(st, ~replaceWhat=stmt.label, ~replaceWith=newLabel) {
                                | Error(msg) => Error(msg)
                                | Ok(st) => {
                                    Ok(st->updateStmt(stmtId, stmt => {...stmt, label:newLabel}))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

let findStmtsToMerge = (st:editorState):result<(userStmt,userStmt),string> => {
    if (st.checkedStmtIds->Js.Array2.length == 1) {
        switch st->editorGetStmtById(st.checkedStmtIds[0]) {
            | None => Error("One statement should be selected [1].")
            | Some(stmt1) => {
                let contStr = stmt1.cont->contToStr
                switch st.stmts->Js.Array2.find(stmt => stmt.id != stmt1.id && stmt.cont->contToStr == contStr) {
                    | None => Error("Cannot find another statement to merge with.")
                    | Some(stmt2) => Ok((stmt1, stmt2))
                }
            }
        }
    } else {
        Error("One statement should be selected [2].")
    }
}