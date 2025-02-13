open MM_wrk_editor
open MM_context
open MM_parser
open MM_proof_tree
open MM_syntax_tree
open MM_wrk_settings
open MM_parenCounter
open MM_substitution
open MM_provers

let verifyTypesForSubstitution = (~parenCnt, ~ctx, ~frms, ~frameRestrict, ~wrkSubs:wrkSubs):unit => {
    let varToExprArr = wrkSubs.subs->Belt_MapInt.toArray
    let typesToProve = varToExprArr->Js_array2.map(((var,expr)) => 
        [ctx->getTypeOfVarExn(var)]->Js.Array2.concat(expr)
    )
    let proofTree = proveFloatings(
        ~wrkCtx=ctx,
        ~frms,
        ~frameRestrict,
        ~floatingsToProve=typesToProve,
        ~parenCnt,
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

let applyWrkSubs = (expr, wrkSubs:wrkSubs): expr => {
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

let findPossibleSubsByMatch = (
    ~wrkCtx:mmContext, 
    ~parenCnt: parenCnt,
    ~frmExpr:expr, 
    ~expr:expr
):result<array<wrkSubs>,string> => {
    let axLabel = generateNewLabels(~ctx=wrkCtx, ~prefix="temp-ax-", ~amount=1, ())[0]
    let tmpFrame = createFrame(
        ~ctx=wrkCtx, ~ord=0, ~isAxiom=false, ~label=axLabel, ~exprStr=wrkCtx->ctxIntsToSymsExn(frmExpr), ~proof=None,
        ~skipEssentials=true, ~skipFirstSymCheck=true, ()
    )
    let frm = prepareFrmSubsDataForFrame(tmpFrame)
    let foundSubs = []
    iterateSubstitutions(
        ~frmExpr=tmpFrame.asrt,
        ~expr,
        ~frmConstParts = frm.frmConstParts[frm.numOfHypsE], 
        ~constParts = frm.constParts[frm.numOfHypsE], 
        ~varGroups = frm.varGroups[frm.numOfHypsE],
        ~subs = frm.subs,
        ~parenCnt,
        ~consumer = subs => {
            let wrkSubs = convertSubsToWrkSubs(~subs, ~tmpFrame, ~ctx=wrkCtx)
            foundSubs->Js_array2.push(wrkSubs)->ignore
            Continue
        }
    )->ignore
    Ok(foundSubs)
}

let makeCannotBuildSyntaxTreeError = (expr:expr, msg:string, ctx:mmContext):string => {
    `Cannot build a syntax tree for the expression '${ctx->ctxIntsToStrExn(expr)}': ${msg}`
}

let buildSyntaxTreesOfSameType = (
    ~wrkCtx:mmContext, 
    ~syntaxTypes:array<int>,
    ~frms: frms,
    ~frameRestrict:frameRestrict,
    ~parenCnt: parenCnt,
    ~expr1:expr, 
    ~expr2:expr,
):result<(syntaxTreeNode,syntaxTreeNode),string> => {
    let syntaxTrees = textToSyntaxTree(
        ~wrkCtx,
        ~syms = [ wrkCtx->ctxIntsToSymsExn(expr1), wrkCtx->ctxIntsToSymsExn(expr2) ],
        ~syntaxTypes,
        ~frms,
        ~frameRestrict,
        ~parenCnt,
        ~lastSyntaxType=None,
        ~onLastSyntaxTypeChange = _ => (),
    )
    @warning("-8")
    switch syntaxTrees {
        | Error(msg) => Error(msg)
        | Ok([tree1,tree2]) => {
            switch tree1 {
                | Error(msg) => Error(makeCannotBuildSyntaxTreeError(expr1, msg, wrkCtx))
                | Ok(tree1) => {
                    switch tree2 {
                        | Error(msg) => Error(makeCannotBuildSyntaxTreeError(expr2, msg, wrkCtx))
                        | Ok(tree2) => {
                            if (tree1.typ == tree2.typ) {
                                Ok((tree1,tree2))
                            } else {
                                let syntaxTreeWithMatchingType = textToSyntaxTree(
                                    ~wrkCtx,
                                    ~syms = [ wrkCtx->ctxIntsToSymsExn(expr1) ],
                                    ~syntaxTypes=[tree2.typ],
                                    ~frms,
                                    ~frameRestrict,
                                    ~parenCnt,
                                    ~lastSyntaxType=None,
                                    ~onLastSyntaxTypeChange = _ => (),
                                )
                                @warning("-8")
                                switch syntaxTreeWithMatchingType {
                                    | Ok([Ok(tree1)]) => Ok((tree1,tree2))
                                    | _ => {
                                        let syntaxTreeWithMatchingType = textToSyntaxTree(
                                            ~wrkCtx,
                                            ~syms = [ wrkCtx->ctxIntsToSymsExn(expr2) ],
                                            ~syntaxTypes=[tree1.typ],
                                            ~frms,
                                            ~frameRestrict,
                                            ~parenCnt,
                                            ~lastSyntaxType=None,
                                            ~onLastSyntaxTypeChange = _ => (),
                                        )
                                        @warning("-8")
                                        switch syntaxTreeWithMatchingType {
                                            | Ok([Ok(tree2)]) => Ok((tree1,tree2))
                                            | _ => {
                                                Error(`Cannot prove the two expressions are of the same type.`)
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
    }
}

let removeTypePrefix = (expr:expr, allTypes:array<int>):expr => {
    if (expr->Js_array2.length > 0 && allTypes->Js_array2.includes(expr[0])) {
        expr->Js_array2.sliceFrom(1)
    } else {
        expr
    }
}

let findPossibleSubsByUnif = (
    ~wrkCtx:mmContext, 
    ~allTypes:array<int>,
    ~syntaxTypes:array<int>,
    ~frms: frms,
    ~frameRestrict:frameRestrict,
    ~parenCnt: parenCnt,
    ~expr1:expr, 
    ~expr2:expr,
    ~metavarPrefix:string,
):result<array<wrkSubs>,string> => {
    let syntaxTrees = buildSyntaxTreesOfSameType( 
        ~wrkCtx, ~syntaxTypes, ~frms, ~frameRestrict, ~parenCnt, 
        ~expr1=removeTypePrefix(expr1, allTypes), 
        ~expr2=removeTypePrefix(expr2, allTypes), 
    )
    switch syntaxTrees {
        | Error(msg) => Error(msg)
        | Ok((tree1,tree2)) => {
            let continue = ref(true)
            let foundSubs = Belt_HashMapString.make(~hintSize = expr1->Js_array2.length + expr2->Js_array2.length)
            unify(tree1, tree2, ~foundSubs, ~continue, ~isMetavar=Js_string2.startsWith(_,metavarPrefix))
            if (!continue.contents) {
                Error(`Cannot unify these expressions.`)
            } else {
                let res = foundSubs->Belt_HashMapString.toArray
                    ->Js.Array2.map(((var,expr)) => (wrkCtx->ctxSymToIntExn(var), wrkCtx->ctxSymsToIntsExn(expr)))
                    ->Belt_HashMapInt.fromArray
                let maxVar = wrkCtx->getNumOfVars-1
                for v in 0 to maxVar {
                    if (!(res->Belt_HashMapInt.has(v))) {
                        res->Belt_HashMapInt.set(v, [v])
                    }
                }
                Ok([{
                    subs: res->Belt_HashMapInt.toArray->Belt_MapInt.fromArray,
                    newDisj: disjMake(),
                    err: None,
                }])
            }
        }
    }
}

let findPossibleSubs = (st:editorState, frmExpr:expr, expr:expr, useMatching:bool):result<array<wrkSubs>,string> => {
    switch st.wrkCtx {
        | None => raise(MmException({msg:`Cannot search for substitutions without wrkCtx.`}))
        | Some(wrkCtx) => {
            let foundSubs = if (useMatching) {
                findPossibleSubsByMatch(~wrkCtx, ~parenCnt=st.parenCnt, ~frmExpr, ~expr)
            } else {
                findPossibleSubsByUnif(
                    ~wrkCtx, 
                    ~allTypes=st.allTypes,
                    ~syntaxTypes=st.syntaxTypes,
                    ~frms=st.frms,
                    ~frameRestrict=st.settings.allowedFrms.inSyntax,
                    ~parenCnt=st.parenCnt,
                    ~expr1=frmExpr, 
                    ~expr2=expr,
                    ~metavarPrefix=st.settings.unifMetavarPrefix,
                )
            }
            switch foundSubs {
                | Error(msg) => Error(msg)
                | Ok(foundSubs) => {
                    let disj = wrkCtx->getAllDisj
                    foundSubs->Js_array2.forEach(wrkSubs => {
                        verifyDisjoints(~wrkSubs, ~disj)
                        if (wrkSubs.err->Belt_Option.isNone) {
                            verifyTypesForSubstitution(
                                ~parenCnt=st.parenCnt, 
                                ~ctx=wrkCtx, 
                                ~frms=st.frms, 
                                ~frameRestrict=st.settings.allowedFrms.inSyntax,
                                ~wrkSubs
                            )
                        }
                    })
                    Ok(foundSubs)
                }
            }
        }
    }
}