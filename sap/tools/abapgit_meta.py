"""Writes the abapGit XML that sits beside every hand-written ABAP / CDS source in sap/src.

The sources (.abap, .asddls, .asbdef, .asddlxs, .asdcls, .srvdsrv) are written by hand.
The XML around them is boilerplate that is easy to get subtly wrong by hand (INTLEN,
masks, class categories), so it is generated from the object list below.

    python sap/tools/abapgit_meta.py          # rewrites every *.xml in sap/src
"""

from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
BOM = "﻿"

ADMIN = [
    ("CREATED_BY", "@ABP_CREATION_USER"),
    ("CREATED_AT", "@ABP_CREATION_TSTMPL"),
    ("LAST_CHANGED_BY", "@ABP_LASTCHANGE_USER"),
    ("LAST_CHANGED_AT", "@ABP_LASTCHANGE_TSTMPL"),
    ("LOCAL_LAST_CHANGED_AT", "@ABP_LOCINST_LASTCHANGE_TSTMPL"),
]
LOCAL_ONLY = [("LOCAL_LAST_CHANGED_AT", "@ABP_LOCINST_LASTCHANGE_TSTMPL")]

# Field spec: (name, type) with type one of
#   CHAR n | NUMC n | DATS | TIMS | INT1 | INT4 | DEC l d | STRG | RSTR | @ROLLNAME
# A leading "*" on the name marks a key field.
TABLES = {
    "ZEST_AI_PROV": ("Estate Command: AI provider configuration", [
        ("*CLIENT", "CLNT"), ("*PROVIDER_ID", "CHAR 20"), ("PROVIDER_TYPE", "CHAR 10"),
        ("DESCRIPTION", "CHAR 60"), ("MODEL_ID", "CHAR 60"), ("COMM_SCENARIO", "CHAR 30"),
        ("OUTBOUND_SERVICE", "CHAR 30"), ("API_PATH", "CHAR 120"), ("API_REVISION", "CHAR 20"),
        ("API_KEY", "STRG"), ("AWS_REGION", "CHAR 20"), ("MAX_TOKENS", "INT4"),
        ("TEMPERATURE", "DEC 3 2"), ("IS_ACTIVE", "@ABAP_BOOLEAN"), ("IS_DEFAULT", "@ABAP_BOOLEAN"),
        ("PRIORITY", "INT4")] + ADMIN),
    "ZEST_ESTATE": ("Estate Command: estate", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("ESTATE_NAME", "CHAR 60"), ("PLANT", "CHAR 4"),
        ("STORAGE_LOCATION", "CHAR 4"), ("LATITUDE", "DEC 10 6"), ("LONGITUDE", "DEC 10 6"),
        ("CURRENCY", "CHAR 5"), ("DEFAULT_PROVIDER", "CHAR 20"), ("IS_SAMPLE", "@ABAP_BOOLEAN"),
        ("DATA_END", "DATS")] + ADMIN),
    "ZEST_BLOCK": ("Estate Command: block (field)", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*BLOCK_KEY", "CHAR 12"),
        ("DIVISION", "CHAR 4"), ("BLOCK_CODE", "CHAR 8"), ("BLOCK_LABEL", "CHAR 16"),
        ("PLANTED_HA", "DEC 9 2"), ("PALMS", "INT4"), ("PLANTED_YEAR", "NUMC 4"),
        ("ABW_KG", "DEC 5 2"), ("ROTATION_DAYS", "INT4"), ("GANG_CODE", "CHAR 10"),
        ("ROAD_CONDITION", "CHAR 20"), ("BUNCHES_PER_DAY", "DEC 11 3"),
        ("CENTROID_LON", "DEC 10 6"), ("CENTROID_LAT", "DEC 10 6"), ("GEOMETRY", "STRG")]),
    "ZEST_CREW": ("Estate Command: crew, gang, team", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*CREW_CODE", "CHAR 10"),
        ("CREW_TYPE", "CHAR 10"), ("CREW_NAME", "CHAR 40"), ("DIVISION", "CHAR 4"),
        ("ESTABLISHMENT", "INT4"), ("HARVESTERS", "INT4"), ("HOME_BLOCK", "CHAR 16")]),
    "ZEST_ATTEND": ("Estate Command: daily attendance per crew", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*CREW_CODE", "CHAR 10"), ("*WORK_DATE", "DATS"),
        ("ON_ROLL", "INT4"), ("PRESENT", "INT4")]),
    "ZEST_WORKORD": ("Estate Command: work-order ledger", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*ORDER_ID", "CHAR 24"),
        ("WORK_DATE", "DATS"), ("OPERATION", "CHAR 10"), ("ACTIVITY", "CHAR 16"),
        ("DIVISION", "CHAR 4"), ("BLOCK_KEY", "CHAR 12"), ("CREW_CODE", "CHAR 10"),
        ("HEADCOUNT_PLAN", "INT4"), ("HEADCOUNT_ACTUAL", "INT4"),
        ("PLANNED_QTY", "DEC 13 2"), ("ACTUAL_QTY", "DEC 13 2"), ("QTY_UNIT", "CHAR 10"),
        ("MAN_DAYS_PLAN", "DEC 9 2"), ("MAN_DAYS_ACTUAL", "DEC 9 2"),
        ("STATUS", "CHAR 16"), ("CARRIED_TO", "CHAR 24")]),
    "ZEST_UPKEEP": ("Estate Command: upkeep round state", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*BLOCK_KEY", "CHAR 12"), ("*ACTIVITY", "CHAR 16"),
        ("LAST_DONE", "DATS"), ("INTERVAL_DAYS", "INT4")]),
    "ZEST_ASSUMP": ("Estate Command: assumption register", [
        ("*CLIENT", "CLNT"), ("*ASSUMPTION_KEY", "CHAR 40"), ("ASSUMPTION_LABEL", "CHAR 80"),
        ("ASSUMPTION_VALUE", "DEC 15 4"), ("DEFAULT_VALUE", "DEC 15 4"), ("VALUE_UNIT", "CHAR 30"),
        ("VALUE_SOURCE", "CHAR 12"), ("BASIS", "STRG"), ("USED_BY", "CHAR 255"),
        ("MIN_VALUE", "DEC 15 4"), ("MAX_VALUE", "DEC 15 4"), ("ASSUMPTION_GROUP", "CHAR 16"),
        ("SORT_ORDER", "INT4")] + ADMIN),
    "ZEST_PLAN": ("Estate Command: tomorrow's assignment", [
        ("*CLIENT", "CLNT"), ("*PLAN_UUID", "@SYSUUID_X16"), ("ESTATE", "CHAR 10"),
        ("OPERATION", "CHAR 10"), ("PLAN_DATE", "DATS"), ("STATUS", "CHAR 1"),
        ("STATUS_CRITICALITY", "INT1"), ("CREWS", "INT4"), ("PRESENT", "INT4"),
        ("CAPACITY_MD", "DEC 11 2"), ("BLOCKS_DUE", "INT4"), ("MAN_DAYS_DUE", "DEC 11 2"),
        ("BLOCKS_ASSIGNED", "INT4"), ("MAN_DAYS_ASSIGNED", "DEC 11 2"),
        ("DEFERRAL_DUE", "DEC 17 0"), ("VALUE_RECOVERED", "DEC 17 0"), ("UPPER_BOUND", "DEC 17 0"),
        ("GAP_PERCENT", "DEC 5 1"), ("CONTIGUITY_COST", "DEC 17 0"), ("CONTIGUITY_PERCENT", "DEC 5 1"),
        ("SWAPS", "INT4"), ("RAIN_MM", "DEC 6 1"), ("RAIN_PROBABILITY", "INT4"),
        ("WEATHER_SOURCE", "CHAR 120"), ("STOPS_WORK", "@ABAP_BOOLEAN"), ("STOP_REASON", "CHAR 255"),
        ("OVERRIDES", "STRG"), ("HEADLINE", "CHAR 255"), ("SUMMARY", "STRG"), ("WHY_TEXT", "STRG"),
        ("AUDIT_CHECKED", "INT4"), ("AUDIT_UNVERIFIED", "CHAR 255"), ("AUDIT_CRITICALITY", "INT1"),
        ("PROVIDER_ID", "CHAR 20"), ("MODEL_ID", "CHAR 60"), ("INPUT_TOKENS", "INT4"),
        ("OUTPUT_TOKENS", "INT4"), ("ERROR_TEXT", "CHAR 255"), ("PROMPT", "STRG"),
        ("RAW_RESPONSE", "STRG"), ("DECIDED_BY", "CHAR 12"), ("DECIDED_AT", "@TIMESTAMPL"),
        ("DECISION_NOTE", "CHAR 255"), ("DUE_DATE", "DATS"), ("EXPECTED_EFFECT", "CHAR 255"),
        ("OBSERVED_EFFECT", "CHAR 255"), ("ARTIFACT_TEXT", "STRG")] + ADMIN),
    "ZEST_PLAN_L": ("Estate Command: assignment line", [
        ("*CLIENT", "CLNT"), ("*LINE_UUID", "@SYSUUID_X16"), ("PLAN_UUID", "@SYSUUID_X16"),
        ("LINE_NO", "INT4"), ("IS_ASSIGNED", "@ABAP_BOOLEAN"), ("CREW_CODE", "CHAR 10"),
        ("CREW_RANGE", "CHAR 80"), ("CREW_PRESENT", "INT4"), ("SEQUENCE_NO", "INT4"),
        ("BLOCK_KEY", "CHAR 12"), ("BLOCK_LABEL", "CHAR 16"), ("DIVISION", "CHAR 4"),
        ("ACTIVITY", "CHAR 16"), ("QUANTITY", "DEC 13 2"), ("QTY_UNIT", "CHAR 10"),
        ("MAN_DAYS", "DEC 9 2"), ("WORK_SHARE", "DEC 5 3"), ("URGENCY", "DEC 7 2"),
        ("DAYS_SINCE", "INT4"), ("TARGET_DAYS", "INT4"), ("BLOCK_VALUE", "DEC 17 0"),
        ("DEFERRAL", "DEC 17 0"), ("CONTIGUITY", "DEC 17 0"), ("TRAVEL_KM", "DEC 9 2"),
        ("TRAVEL_COST", "DEC 17 0"), ("SCORE", "DEC 17 0"), ("IS_CONTIGUOUS", "@ABAP_BOOLEAN"),
        ("ROAD_CONDITION", "CHAR 20"), ("CRITICALITY", "INT1"), ("LINE_NOTE", "CHAR 120")] + LOCAL_ONLY),
    "ZEST_IMPORT": ("Estate Command: data import file", [
        ("*CLIENT", "CLNT"), ("*IMPORT_UUID", "@SYSUUID_X16"), ("DATA_KIND", "CHAR 20"),
        ("ESTATE", "CHAR 10"), ("FILE_NAME", "CHAR 128"), ("MIME_TYPE", "CHAR 128"),
        ("ATTACHMENT", "RSTR"), ("STATUS", "CHAR 1"), ("STATUS_CRITICALITY", "INT1"),
        ("ROWS_LOADED", "INT4"), ("MESSAGE", "CHAR 255")] + ADMIN),
    "ZEST_MM_MOCK": ("Estate Command: sample SAP MM records", [
        ("*CLIENT", "CLNT"), ("*ESTATE", "CHAR 10"), ("*ROW_ID", "INT4"), ("KIND", "CHAR 1"),
        ("MATERIAL", "CHAR 40"), ("MATERIAL_NAME", "CHAR 60"), ("MATERIAL_GROUP", "CHAR 9"),
        ("SUPPLIER", "CHAR 10"), ("SUPPLIER_NAME", "CHAR 60"), ("DOCUMENT", "CHAR 10"),
        ("DATE_OFFSET", "INT4"), ("DATE2_OFFSET", "INT4"), ("QUANTITY", "DEC 15 3"),
        ("QTY_UNIT", "CHAR 3"), ("QUOTED_DAYS", "INT4"), ("REORDER_POINT", "DEC 15 3"),
        ("SAFETY_STOCK", "DEC 15 3"), ("ROUNDING", "DEC 15 3"), ("PRICE", "DEC 15 2")]),
}

# name: (description, category) ; category None = normal, "40" exception, "06" behavior pool
CLASSES = {
    "ZCX_EST_AI": ("Estate Command: AI and integration error", "40"),
    "ZCL_EST_AI_HTTP": ("Estate Command: outbound HTTP for AI and feeds", None),
    "ZCL_EST_AI_FACTORY": ("Estate Command: AI provider factory", None),
    "ZCL_EST_AI_BEDROCK": ("Estate Command: Amazon Bedrock Converse", None),
    "ZCL_EST_AI_GEMINI": ("Estate Command: Google Gemini", None),
    "ZCL_EST_AI_BYTEPLUS": ("Estate Command: BytePlus ModelArk", None),
    "ZCL_EST_AI_TEST": ("Estate Command: providers, plans, stores smoke test", None),
    "ZCL_EST_SEED": ("Estate Command: register, providers, sample estate", None),
    "ZCL_EST_ASSUMPTIONS": ("Estate Command: assumption register", None),
    "ZCL_EST_DATA": ("Estate Command: estate state", None),
    "ZCL_EST_GEO": ("Estate Command: geometry", None),
    "ZCL_EST_DEMAND": ("Estate Command: what is due tomorrow", None),
    "ZCL_EST_SCHEDULER": ("Estate Command: tomorrow's assignment", None),
    "ZCL_EST_WEATHER": ("Estate Command: Open-Meteo forecast", None),
    "ZCL_EST_AUDIT": ("Estate Command: figure audit", None),
    "ZCL_EST_PLAN_BUILDER": ("Estate Command: plan with AI words", None),
    "ZCL_EST_PLAN_JOB": ("Application job: tomorrow's plans", None),
    "ZCL_EST_IMPORT": ("Estate Command: CSV import", None),
    "ZCL_EST_MM_DATA": ("Estate Command: SAP MM reads", None),
    "ZCL_EST_STORES": ("Estate Command: what to order and when", None),
    "ZCL_EST_STORES_QUERY": ("Estate Command: stores query provider", None),
    "ZBP_R_EST_PLAN": ("Behavior Definition for ZR_EST_PLAN", "06"),
    "ZBP_R_EST_ASSUMP": ("Behavior Definition for ZR_EST_ASSUMP", "06"),
    "ZBP_R_EST_ESTATE": ("Behavior Definition for ZR_EST_ESTATE", "06"),
    "ZBP_R_EST_IMPORT": ("Behavior Definition for ZR_EST_IMPORT", "06"),
    "ZBP_R_EST_AI_PROV": ("Behavior Definition for ZR_EST_AI_PROV", "06"),
}

INTERFACES = {"ZIF_EST_AI_PROVIDER": "Estate Command: AI provider"}

DDLS = {
    "ZI_EST_AI_PROV_VH": "AI Provider",
    "ZI_EST_ESTATE_VH": "Estate",
    "ZI_EST_BLOCK": "Estate Block",
    "ZR_EST_AI_PROV": "AI Provider",
    "ZC_EST_AI_PROV": "AI Provider",
    "ZR_EST_PLAN": "Tomorrow's Assignment",
    "ZR_EST_PLAN_L": "Assignment Line",
    "ZC_EST_PLAN": "Tomorrow's Assignment",
    "ZC_EST_PLAN_L": "Assignment Line",
    "ZR_EST_ASSUMP": "Assumption",
    "ZC_EST_ASSUMP": "Assumption",
    "ZR_EST_ESTATE": "Estate",
    "ZC_EST_ESTATE": "Estate",
    "ZR_EST_IMPORT": "Data Import",
    "ZC_EST_IMPORT": "Data Import",
    "ZI_EST_STORES": "Stores: What to Order",
    "ZA_EST_GEN_PLAN": "Generate Plan Parameters",
    "ZA_EST_REPLAN": "Replan Parameters",
    "ZA_EST_PROVIDER": "AI Provider Parameter",
    "ZA_EST_DECISION": "Decision Parameters",
    "ZA_EST_QUESTION": "Question",
    "ZA_EST_ANSWER": "Answer",
    "ZA_EST_ESTATE_P": "Estate Parameter",
    "ZA_EST_HANDOVER": "Shift Handover",
    "ZA_EST_OUTCOME": "Plan Outcome",
}

DDLX = ["ZC_EST_AI_PROV", "ZC_EST_PLAN", "ZC_EST_PLAN_L", "ZC_EST_ASSUMP", "ZC_EST_ESTATE", "ZC_EST_IMPORT", "ZI_EST_STORES"]
DCLS = ["ZR_EST_PLAN", "ZC_EST_PLAN"]
BDEF = ["ZR_EST_AI_PROV", "ZC_EST_AI_PROV", "ZR_EST_PLAN", "ZC_EST_PLAN", "ZR_EST_ASSUMP", "ZC_EST_ASSUMP",
        "ZR_EST_ESTATE", "ZC_EST_ESTATE", "ZR_EST_IMPORT", "ZC_EST_IMPORT"]
SRVD = {"ZUI_EST_CMD_O4": "Estate Command service"}
SRVB = {"ZUI_EST_CMD_O4": "ZUI_EST_CMD_O4"}


def _wrap(serializer: str, body: str) -> str:
    return (f'{BOM}<?xml version="1.0" encoding="utf-8"?>\n'
            f'<abapGit version="v1.0.0" serializer="{serializer}" serializer_version="v1.0.0">\n'
            ' <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">\n'
            '  <asx:values>\n'
            f'{body}'
            '  </asx:values>\n'
            ' </asx:abap>\n'
            '</abapGit>\n')


def _field(name: str, spec: str) -> str:
    key = name.startswith("*")
    name = name.lstrip("*")
    lines = [f"     <FIELDNAME>{name}</FIELDNAME>"]
    if key:
        lines.append("     <KEYFLAG>X</KEYFLAG>")
    if spec.startswith("@"):
        lines += [f"     <ROLLNAME>{spec[1:]}</ROLLNAME>", "     <ADMINFIELD>0</ADMINFIELD>"]
        if key:
            lines.append("     <NOTNULL>X</NOTNULL>")
        lines.append("     <COMPTYPE>E</COMPTYPE>")
    else:
        parts = spec.split()
        t = parts[0]
        if t == "CLNT":
            inttype, intlen, leng, dec = "C", 6, 3, None
        elif t in ("CHAR", "NUMC"):
            n = int(parts[1])
            inttype, intlen, leng, dec = ("C" if t == "CHAR" else "N"), 2 * n, n, None
        elif t == "DATS":
            inttype, intlen, leng, dec = "D", 16, 8, None
        elif t == "TIMS":
            inttype, intlen, leng, dec = "T", 12, 6, None
        elif t == "INT1":
            inttype, intlen, leng, dec = "X", 1, 3, None
        elif t == "INT4":
            inttype, intlen, leng, dec = "X", 4, 10, None
        elif t == "DEC":
            n, d = int(parts[1]), int(parts[2])
            inttype, intlen, leng, dec = "P", n // 2 + 1, n, d
        elif t == "STRG":
            inttype, intlen, leng, dec = "g", 8, None, None
        elif t == "RSTR":
            inttype, intlen, leng, dec = "y", 8, None, None
        else:
            raise ValueError(spec)
        lines += ["     <ADMINFIELD>0</ADMINFIELD>", f"     <INTTYPE>{inttype}</INTTYPE>",
                  f"     <INTLEN>{intlen:06d}</INTLEN>"]
        if key:
            lines.append("     <NOTNULL>X</NOTNULL>")
        lines.append(f"     <DATATYPE>{t}</DATATYPE>")
        if leng is not None:
            lines.append(f"     <LENG>{leng:06d}</LENG>")
        if dec:
            lines.append(f"     <DECIMALS>{dec:06d}</DECIMALS>")
        lines.append(f"     <MASK>  {t}</MASK>")
        if t == "DATS":
            lines.append("     <SHLPORIGIN>T</SHLPORIGIN>")
    return "    <DD03P>\n" + "\n".join(lines) + "\n    </DD03P>\n"


def table(name: str, text: str, fields: list) -> str:
    body = ("   <DD02V>\n"
            f"    <TABNAME>{name}</TABNAME>\n"
            "    <DDLANGUAGE>E</DDLANGUAGE>\n"
            "    <TABCLASS>TRANSP</TABCLASS>\n"
            "    <CLIDEP>X</CLIDEP>\n"
            f"    <DDTEXT>{text}</DDTEXT>\n"
            "    <MASTERLANG>E</MASTERLANG>\n"
            "    <CONTFLAG>A</CONTFLAG>\n"
            "    <EXCLASS>1</EXCLASS>\n"
            "   </DD02V>\n"
            "   <DD09L>\n"
            f"    <TABNAME>{name}</TABNAME>\n"
            "    <AS4LOCAL>A</AS4LOCAL>\n"
            "    <TABKAT>0</TABKAT>\n"
            "    <TABART>APPL0</TABART>\n"
            "    <BUFALLOW>N</BUFALLOW>\n"
            "   </DD09L>\n"
            "   <DD03P_TABLE>\n"
            + "".join(_field(n, s) for n, s in fields) +
            "   </DD03P_TABLE>\n")
    return _wrap("LCL_OBJECT_TABL", body)


def clas(name: str, text: str, category: str | None) -> str:
    lines = [f"    <CLSNAME>{name}</CLSNAME>", "    <LANGU>E</LANGU>", f"    <DESCRIPT>{text}</DESCRIPT>"]
    if category:
        lines.append(f"    <CATEGORY>{category}</CATEGORY>")
    lines.append("    <STATE>1</STATE>")
    if category == "06" or (SRC / f"{name.lower()}.clas.locals_imp.abap").exists():
        lines.append("    <CLSCCINCL>X</CLSCCINCL>")
    lines += ["    <FIXPT>X</FIXPT>", "    <UNICODE>X</UNICODE>"]
    if category == "06":
        lines.append(f"    <CLSDEFINT>{name.replace('ZBP_', 'Z')}</CLSDEFINT>")
    return _wrap("LCL_OBJECT_CLAS", "   <VSEOCLASS>\n" + "\n".join(lines) + "\n   </VSEOCLASS>\n")


def intf(name: str, text: str) -> str:
    return _wrap("LCL_OBJECT_INTF", "   <VSEOINTERF>\n"
                 f"    <CLSNAME>{name}</CLSNAME>\n    <LANGU>E</LANGU>\n    <DESCRIPT>{text}</DESCRIPT>\n"
                 "    <EXPOSURE>2</EXPOSURE>\n    <STATE>1</STATE>\n    <UNICODE>X</UNICODE>\n"
                 "   </VSEOINTERF>\n")


def ddls(name: str, text: str) -> str:
    src = (SRC / f"{name.lower()}.ddls.asddls").read_text(encoding="utf-8")
    kind = "A" if "abstract entity" in src else ("Q" if "custom entity" in src else
           ("P" if "projection on" in src else "W"))
    return _wrap("LCL_OBJECT_DDLS", "   <DDLS>\n"
                 f"    <DDLNAME>{name}</DDLNAME>\n    <DDLANGUAGE>E</DDLANGUAGE>\n"
                 f"    <DDTEXT>{text}</DDTEXT>\n    <SOURCE_TYPE>{kind}</SOURCE_TYPE>\n   </DDLS>\n")


def ddlx(name: str) -> str:
    return _wrap("LCL_OBJECT_DDLX", "   <DDLX>\n    <METADATA>\n"
                 f"     <NAME>{name}</NAME>\n     <DESCRIPTION>Metadata Extension for {name}</DESCRIPTION>\n"
                 "     <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>\n    </METADATA>\n   </DDLX>\n")


def dcls(name: str) -> str:
    return _wrap("LCL_OBJECT_DCLS", "   <DCLS>\n"
                 f"    <DCLNAME>{name}</DCLNAME>\n    <DCL_TYPE>ROLE</DCL_TYPE>\n    <MASTERLANG>E</MASTERLANG>\n"
                 f"    <LANGUAGE>E</LANGUAGE>\n    <SHORT_TEXT>Access Control for {name}</SHORT_TEXT>\n"
                 "    <ABAP_LANGUAGE_VERSION>5</ABAP_LANGUAGE_VERSION>\n   </DCLS>\n")


def bdef(name: str) -> str:
    low = name.lower()
    return _wrap("LCL_OBJECT_BDEF", "   <BDEF>\n"
                 f"    <NAME>{name}</NAME>\n    <TYPE>BDEF/BDO</TYPE>\n"
                 f"    <DESCRIPTION>Behavior Definition for {name}</DESCRIPTION>\n"
                 "    <DESCRIPTION_TEXT_LIMIT>60</DESCRIPTION_TEXT_LIMIT>\n    <LANGUAGE>EN</LANGUAGE>\n"
                 "    <LINKS>\n"
                 "     <item>\n"
                 f"      <HREF>./{low}/source/main/versions</HREF>\n"
                 "      <REL>http://www.sap.com/adt/relations/versions</REL>\n"
                 "      <TITLE>Historic versions</TITLE>\n"
                 "     </item>\n"
                 "     <item>\n"
                 f"      <HREF>./{low}/source/main</HREF>\n"
                 "      <REL>http://www.sap.com/adt/relations/source</REL>\n"
                 "      <TYPE>text/plain</TYPE>\n"
                 "      <TITLE>Source Content</TITLE>\n"
                 "     </item>\n"
                 "    </LINKS>\n"
                 "    <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>\n    <ABAP_LANGU_VERSION>5</ABAP_LANGU_VERSION>\n"
                 f"    <SOURCE_URI>./{low}/source/main</SOURCE_URI>\n    <SOURCE_TYPE>ABAP_SOURCE</SOURCE_TYPE>\n"
                 "    <SOURCE_FIXED_POINT_ARITHMETIC>true</SOURCE_FIXED_POINT_ARITHMETIC>\n"
                 "    <SOURCE_UNICODE_CHECKS_ACTIVE>true</SOURCE_UNICODE_CHECKS_ACTIVE>\n   </BDEF>\n")


def srvd(name: str, text: str) -> str:
    return _wrap("LCL_OBJECT_SRVD", "   <SRVD>\n"
                 f"    <NAME>{name}</NAME>\n    <TYPE>SRVD/SRV</TYPE>\n    <DESCRIPTION>{text}</DESCRIPTION>\n"
                 "    <LANGUAGE>EN</LANGUAGE>\n    <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>\n"
                 f"    <SOURCE_URI>./{name.lower()}/source/main</SOURCE_URI>\n    <SOURCE_TYPE>ABAP_SOURCE</SOURCE_TYPE>\n"
                 "    <SOURCE_ORIGIN_DESCRIPTION>ABAP Development Tools</SOURCE_ORIGIN_DESCRIPTION>\n"
                 "    <SRVD_SOURCE_TYPE>S</SRVD_SOURCE_TYPE>\n    <SRVD_SOURCE_TYPE_DESC>Definition</SRVD_SOURCE_TYPE_DESC>\n"
                 "   </SRVD>\n")


def srvb(name: str, definition: str) -> str:
    return _wrap("LCL_OBJECT_SRVB", "   <SRVB>\n    <METADATA>\n"
                 f"     <NAME>{name}</NAME>\n     <TYPE>SRVB/SVB</TYPE>\n"
                 f"     <DESCRIPTION>Service Binding for {definition}</DESCRIPTION>\n"
                 "     <LANGUAGE>EN</LANGUAGE>\n     <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>\n"
                 "     <ABAP_LANGU_VERSION>5</ABAP_LANGU_VERSION>\n    </METADATA>\n    <CONTENT>\n"
                 f"     <BIND_TYPE_IMPL>\n      <NAME>{name}</NAME>\n     </BIND_TYPE_IMPL>\n"
                 "     <BIND_TYPE>ODATA</BIND_TYPE>\n     <BIND_TYPE_VERSION>V4</BIND_TYPE_VERSION>\n"
                 "     <SERVICES>\n      <item>\n"
                 f"       <SERVICE_NAME>{name}</SERVICE_NAME>\n       <SERVICE_CONTENT>\n        <item>\n"
                 "         <SERVICE_VERSION>0001</SERVICE_VERSION>\n         <RELEASE_STATE>NOT_RELEASED</RELEASE_STATE>\n"
                 "         <SRVD_REF>\n"
                 f"          <URI>/sap/bc/adt/ddic/srvd/sources/{definition.lower()}</URI>\n"
                 f"          <TYPE>SRVD/SRV</TYPE>\n          <NAME>{definition}</NAME>\n"
                 "         </SRVD_REF>\n        </item>\n       </SERVICE_CONTENT>\n      </item>\n     </SERVICES>\n"
                 "    </CONTENT>\n    <CONTRACT>C1</CONTRACT>\n    <RELEASE_SUPPORTED>true</RELEASE_SUPPORTED>\n"
                 "   </SRVB>\n")


PACKAGE = _wrap("LCL_OBJECT_DEVC", "   <DEVC>\n    <CTEXT>Estate Command on SAP</CTEXT>\n"
                "    <LANGUAGE>E</LANGUAGE>\n    <MASTERLANG>E</MASTERLANG>\n    <SRV_CHECK>X</SRV_CHECK>\n   </DEVC>\n")


def main() -> None:
    out = {"package.devc.xml": PACKAGE}
    for n, (t, f) in TABLES.items():
        out[f"{n.lower()}.tabl.xml"] = table(n, t, f)
    for n, (t, c) in CLASSES.items():
        out[f"{n.lower()}.clas.xml"] = clas(n, t, c)
    for n, t in INTERFACES.items():
        out[f"{n.lower()}.intf.xml"] = intf(n, t)
    for n, t in DDLS.items():
        out[f"{n.lower()}.ddls.xml"] = ddls(n, t)
    for n in DDLX:
        out[f"{n.lower()}.ddlx.xml"] = ddlx(n)
    for n in DCLS:
        out[f"{n.lower()}.dcls.xml"] = dcls(n)
    for n in BDEF:
        out[f"{n.lower()}.bdef.xml"] = bdef(n)
    for n, t in SRVD.items():
        out[f"{n.lower()}.srvd.xml"] = srvd(n, t)
    for n, d in SRVB.items():
        out[f"{n.lower()}.srvb.xml"] = srvb(n, d)
    for name, text in out.items():
        (SRC / name).write_text(text, encoding="utf-8")
    print(f"{len(out)} XML files written to {SRC}")


if __name__ == "__main__":
    main()
