open MM_syntax_tree
open Expln_React_common
open Expln_React_Mui
open MM_wrk_editor
open MM_react_common
open MM_context
open MM_substitution
open MM_parenCounter
open MM_proof_tree
open MM_proof_tree_dto
open Expln_React_Modal
open Local_storage_utils
open Common
open MM_cmp_user_stmt
open MM_cmp_pe_frame_summary_state

let paddingLeft = "5px"
let paddingRight = paddingLeft

let disjGrpDelim = nbsp ++ nbsp ++ nbsp ++ nbsp

type props = {
    modalRef:modalRef,
    typeColors:Belt_HashMapString.t<string>,
    editStmtsByLeftClick:bool,

    preCtx:mmContext,
    syntaxTypes:array<int>,
    frms: Belt_MapString.t<frmSubsData>,
    parenCnt: parenCnt,

    frame:frame,
    order:int,
    openFrameExplorer:string=>unit,
}

let propsAreSame = (a:props,b:props):bool => {
    a.typeColors === b.typeColors
    && a.editStmtsByLeftClick === b.editStmtsByLeftClick
    && a.preCtx === b.preCtx
    && a.frame === b.frame
    && a.order === b.order
}

let make = React.memoCustomCompareProps( ({
    modalRef,
    typeColors,
    editStmtsByLeftClick,
    preCtx,
    syntaxTypes,
    frms,
    parenCnt,
    frame,
    order,
    openFrameExplorer,
}:props) =>  {
    let (state, setState) = React.useState(_ => makeInitialState(~preCtx, ~frame, ~typeColors))

    React.useEffect5(() => {
        setState(_ => makeInitialState(~preCtx, ~frame, ~typeColors))
        None
    }, (typeColors, editStmtsByLeftClick, preCtx, frame, order))

    let actToggleDescrIsExpanded = () => {
        setState(toggleDescrIsExpanded)
    }

    let rndExpBtn = () => {
        if (frame.descr->Belt.Option.isSome) {
            <span>
                {React.string(nbsp ++ nbsp)}
                <span 
                    onClick=clickHnd(~act=actToggleDescrIsExpanded,())
                    style=ReactDOM.Style.make(
                        ~display="inline-block", 
                        ~transform=if(state.descrIsExpanded) {"rotate(90deg)"} else {"none"},
                        ~fontFamily="monospace",
                        ~fontSize="1.5em",
                        ~color="grey",
                        ~fontWeight="bold",
                        ~cursor="pointer",
                        ()
                    )
                >
                    { React.string( ">" ) }
                </span>
            </span>
        } else {
            <></>
        }
    }

    let rndLabel = ():reElem => {
        let asrtType = if (frame.isAxiom) {
            <span style=ReactDOM.Style.make(~color="red", ())>
                {"Axiom"->React.string}
            </span>
        } else {
            <span style=ReactDOM.Style.make(~color="green", ())>
                {"Theorem"->React.string}
            </span>
        }
        <span style=ReactDOM.Style.make(~paddingLeft, ~paddingRight, ()) >
            { React.string( order->Belt_Int.toString ++ " ") }
            asrtType
            <span 
                style=ReactDOM.Style.make(~fontWeight="bold", ~cursor="pointer", ())
                onClick=clickHnd(~act=()=>openFrameExplorer(frame.label), ())
            >
                { (" " ++ frame.label)->React.string }
            </span>
            {rndExpBtn()}
        </span>
    }

    let rndDescr = () => {
        if (frame.descr->Belt.Option.isSome && state.descrIsExpanded) {
            <>
                <Divider/>
                <div style=ReactDOM.Style.make(~paddingLeft, ~paddingRight, ())>
                    {
                        frame.descr->Belt.Option.getWithDefault("This assertion doesn't have any description.")->React.string
                    }
                </div>
            </>
        } else {
            <></>
        }
    }

    let rndDisjGrp = (grp:array<(string,option<string>)>):reElem => {
        let res = []
        for i in 0 to grp->Js.Array2.length-1 {
            if (i > 0) {
                res->Js.Array2.push(
                    <span
                        key={"s-" ++ i->Belt_Int.toString}
                        style=ReactDOM.Style.make(
                            ~color="black",
                            ~fontFamily="monospace",
                            ~fontSize="1.3em",
                            ~fontWeight="normal",
                            ()
                        )
                    >
                        {","->React.string}
                    </span>
                )->ignore
            }
            let (sym,colorOpt) = grp[i]
            res->Js.Array2.push(
                <span
                    key={"v-" ++ i->Belt_Int.toString}
                    style=ReactDOM.Style.make(
                        ~color=?colorOpt,
                        ~fontFamily="monospace",
                        ~fontSize="1.3em",
                        ~fontWeight="bold",
                        ()
                    )
                >
                    {sym->React.string}
                </span>
            )->ignore
        }
        res->React.array
    }

    let rndDisj = () => {
        switch state.disj {
            | None => <span style=ReactDOM.Style.make(~display="none", ()) />
            | Some(disj) => {
                let disjGrpArr = []
                for i in 0 to disj->Js.Array2.length-1 {
                    let grp = disj[i]
                    if (i > 0) {
                        disjGrpArr->Js.Array2.push(
                            <span key={"s-" ++ i->Belt_Int.toString} >
                                {disjGrpDelim->React.string}
                            </span>
                        )->ignore
                    }
                    disjGrpArr->Js.Array2.push(
                        <span key={"g-" ++ i->Belt_Int.toString} >
                            {rndDisjGrp(grp)}
                        </span>
                    )->ignore
                }
                <>
                    <Divider/>
                    <span style=ReactDOM.Style.make(~paddingLeft, ~paddingRight, ())>
                        { (`Disj:` ++ disjGrpDelim)->React.string }
                        {disjGrpArr->React.array}
                    </span>
                </>
            }
        }
    }

    let rndHyps = () => {
        if (state.eHyps->Js.Array2.length == 0) {
            <></>
        } else {
            state.eHyps->Js.Array2.mapi((hyp,i) => {
                <React.Fragment key={i->Belt.Int.toString}>
                    <Divider/>
                    <table style=ReactDOM.Style.make(~paddingLeft, ~paddingRight, ())>
                        <tbody>
                            <tr>
                                <td style=ReactDOM.Style.make(~verticalAlign="top", ())>
                                    <span style=ReactDOM.Style.make(~marginLeft="10px", ())>
                                        {circleChar->React.string}
                                    </span>
                                </td>
                                <td>
                                    <MM_cmp_pe_stmt
                                        modalRef
                                        ctx=state.frmCtx
                                        syntaxTypes
                                        frms
                                        parenCnt
                                        stmt=hyp
                                        symColors=state.symColors
                                        symRename=state.symRename
                                        editStmtsByLeftClick
                                    />
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </React.Fragment>
            })->React.array
        }
    }

    let rndAsrt = () => {
        <div style=ReactDOM.Style.make(~paddingLeft, ~paddingRight, ())>
            <MM_cmp_pe_stmt
                modalRef
                ctx=state.frmCtx
                syntaxTypes
                frms
                parenCnt
                stmt=state.asrt
                symColors=state.symColors
                symRename=state.symRename
                editStmtsByLeftClick
            />
        </div>
    }

    <table>
        <tbody>
            <tr>
                <td>
                    <Paper elevation=3 style=ReactDOM.Style.make(~backgroundColor="rgb(255,255,235)", ())>
                        {rndLabel()}
                        {rndDescr()}
                        {rndDisj()}
                        {rndHyps()}
                        <Divider/>
                        {rndAsrt()}
                    </Paper>
                </td>
            </tr>
        </tbody>
    </table>


}, propsAreSame)