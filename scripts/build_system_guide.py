"""Builds docs/how-the-system-works.pdf: the full guide to the Bravura
Electrical Department system."""
import sys
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, Image, KeepTogether, NextPageTemplate, PageBreak,
    PageTemplate, Paragraph, Spacer, Table, TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon

REPO = sys.argv[1]
OUT = sys.argv[2]
FONTS = f"{REPO}/app/assets/fonts"
for name, file in [("Inter", "Inter-Regular"), ("Inter-Medium", "Inter-Medium"),
                   ("Inter-SemiBold", "Inter-SemiBold"), ("Inter-Bold", "Inter-Bold"),
                   ("Inter-ExtraBold", "Inter-ExtraBold")]:
    pdfmetrics.registerFont(TTFont(name, f"{FONTS}/{file}.ttf"))
pdfmetrics.registerFontFamily("Inter", normal="Inter", bold="Inter-Bold",
                              italic="Inter", boldItalic="Inter-Bold")

MAROON = colors.HexColor("#982329")
DEEP = colors.HexColor("#5C1219")
ROSE = colors.HexColor("#E8A0AE")
BLUSH = colors.HexColor("#FBEFF1")
INK = colors.HexColor("#22171A")
MUTED = colors.HexColor("#6B5A5D")
LINE = colors.HexColor("#E6D6D9")
BLUE = colors.HexColor("#3E6FD8")
GREEN = colors.HexColor("#2E9B6A")
AMBER = colors.HexColor("#D98A1C")
RED = colors.HexColor("#C8423B")

base = ParagraphStyle("base", fontName="Inter", fontSize=9.6, leading=14, textColor=INK)
S = {
    "body": base,
    "small": ParagraphStyle("small", parent=base, fontSize=8.4, leading=11.5, textColor=MUTED),
    "h1": ParagraphStyle("h1", parent=base, fontName="Inter-ExtraBold", fontSize=20, leading=25,
                         textColor=MAROON, spaceBefore=4, spaceAfter=8),
    "h2": ParagraphStyle("h2", parent=base, fontName="Inter-Bold", fontSize=12.5, leading=17,
                         textColor=DEEP, spaceBefore=10, spaceAfter=4),
    "h3": ParagraphStyle("h3", parent=base, fontName="Inter-SemiBold", fontSize=10.4, leading=14,
                         textColor=INK, spaceBefore=6, spaceAfter=2),
    "bullet": ParagraphStyle("bullet", parent=base, leftIndent=12, bulletIndent=2, spaceAfter=1.5),
    "cell": ParagraphStyle("cell", parent=base, fontSize=8.6, leading=11.5),
    "cellb": ParagraphStyle("cellb", parent=base, fontName="Inter-SemiBold", fontSize=8.6, leading=11.5),
    "head": ParagraphStyle("head", parent=base, fontName="Inter-SemiBold", fontSize=8.6, leading=11.5,
                           textColor=colors.white),
    "note": ParagraphStyle("note", parent=base, fontSize=9, leading=13, textColor=DEEP),
    "toc1": ParagraphStyle("toc1", parent=base, fontName="Inter-Medium", fontSize=10, leading=16,
                           leftIndent=4),
}

story = []
section_no = [0]


def h1(text):
    section_no[0] += 1
    title = f"{section_no[0]}. {text}"
    p = Paragraph(title, S["h1"])
    p._toc = title
    story.append(p)


def h2(text):
    story.append(Paragraph(text, S["h2"]))


def h3(text):
    story.append(Paragraph(text, S["h3"]))


def p(text):
    story.append(Paragraph(text, S["body"]))
    story.append(Spacer(1, 4))


def bullets(items):
    for it in items:
        story.append(Paragraph(it, S["bullet"], bulletText="•"))
    story.append(Spacer(1, 4))


def table(rows, widths, head=True):
    data = []
    for i, r in enumerate(rows):
        style = "head" if (head and i == 0) else "cell"
        data.append([Paragraph(str(c), S["cellb"] if (style == "cell" and j == 0) else S[style])
                     for j, c in enumerate(r)])
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if head else 0)
    st = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, LINE),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
    ]
    if head:
        st += [("BACKGROUND", (0, 0), (-1, 0), MAROON)]
        st += [("BACKGROUND", (0, i), (-1, i), BLUSH) for i in range(2, len(rows), 2)]
    t.setStyle(TableStyle(st))
    story.append(t)
    story.append(Spacer(1, 8))


def note(text):
    t = Table([[Paragraph(text, S["note"])]], colWidths=[170 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), BLUSH),
        ("LINEBEFORE", (0, 0), (0, -1), 3, MAROON),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(t)
    story.append(Spacer(1, 8))


# ---------------------------------------------------------------------------
# Diagrams
# ---------------------------------------------------------------------------
def box(d, x, y, w, h, title, sub=None, fill=BLUSH, stroke=MAROON, tc=DEEP):
    d.add(Rect(x, y, w, h, rx=6, ry=6, fillColor=fill, strokeColor=stroke, strokeWidth=1))
    d.add(String(x + w / 2, y + h - 13, title, fontName="Inter-Bold", fontSize=8.6,
                 fillColor=tc, textAnchor="middle"))
    if sub:
        for i, line in enumerate(sub):
            d.add(String(x + w / 2, y + h - 25 - i * 10, line, fontName="Inter", fontSize=7,
                         fillColor=MUTED, textAnchor="middle"))


def arrow(d, x1, y1, x2, y2, color=MAROON, label=None):
    d.add(Line(x1, y1, x2, y2, strokeColor=color, strokeWidth=1))
    import math
    a = math.atan2(y2 - y1, x2 - x1)
    s = 5
    d.add(Polygon([x2, y2, x2 - s * math.cos(a - 0.4), y2 - s * math.sin(a - 0.4),
                   x2 - s * math.cos(a + 0.4), y2 - s * math.sin(a + 0.4)],
                  fillColor=color, strokeColor=color))
    if label:
        d.add(String((x1 + x2) / 2 + 3, (y1 + y2) / 2 + 3, label, fontName="Inter", fontSize=6.5,
                     fillColor=MUTED))


def architecture():
    d = Drawing(170 * mm, 112 * mm)
    W = 170 * mm
    # people
    box(d, 8, 262, 140, 44, "Phones (Android app)", ["works offline: outbox", "push alerts, calls"])
    box(d, 175, 262, 140, 44, "Browsers (web app)", ["same app, any PC", "hosted on Vercel"])
    box(d, 342, 262, 130, 44, "Admins and supervisors", ["settings, approvals,", "statistics, imports"])
    # supabase core
    d.add(Rect(8, 110, W - 16, 128, rx=8, ry=8, fillColor=colors.HexColor("#FFF7F8"),
               strokeColor=MAROON, strokeWidth=1.3))
    d.add(String(W / 2, 224, "Supabase (the server)", fontName="Inter-ExtraBold", fontSize=9.5,
                 fillColor=MAROON, textAnchor="middle"))
    box(d, 20, 150, 102, 62, "Sign-in", ["accounts, sessions", "password reset"], fill=colors.white)
    box(d, 130, 150, 102, 62, "Database", ["every record,", "rules on every row,", "39 migrations"],
        fill=colors.white)
    box(d, 240, 150, 102, 62, "Functions", ["fn_* do every change", "and check permission"],
        fill=colors.white)
    box(d, 350, 150, 112, 62, "Files and timers", ["photos, PDFs, drawings", "scheduled jobs (cron)"],
        fill=colors.white)
    d.add(String(W / 2, 122, "Realtime updates  ·  activity log of every change  ·  nightly encrypted backup",
                 fontName="Inter", fontSize=7.2, fillColor=MUTED, textAnchor="middle"))
    for x in (78, 245, 407):
        arrow(d, x, 262, x, 240)
    # outside services
    box(d, 8, 22, 104, 62, "Firebase", ["push notifications", "to phones"], fill=colors.white, stroke=BLUE,
        tc=BLUE)
    box(d, 122, 22, 104, 62, "LiveKit", ["voice and video calls", "in chats"], fill=colors.white, stroke=BLUE,
        tc=BLUE)
    box(d, 236, 22, 104, 62, "GitHub", ["code, checks, deploys,", "APK releases, backups"],
        fill=colors.white, stroke=BLUE, tc=BLUE)
    box(d, 350, 22, 112, 62, "Vercel", ["serves the web app"], fill=colors.white, stroke=BLUE, tc=BLUE)
    for x in (60, 174, 288, 406):
        arrow(d, x, 110, x, 86, color=BLUE)
    return d


def job_flow():
    d = Drawing(170 * mm, 118 * mm)
    w, h = 92, 30

    def st(x, y, label, fill=BLUSH, stroke=MAROON):
        d.add(Rect(x, y, w, h, rx=6, ry=6, fillColor=fill, strokeColor=stroke, strokeWidth=1))
        lines = label.split("\n")
        for i, l in enumerate(lines):
            d.add(String(x + w / 2, y + h / 2 + 3 - i * 9 + (len(lines) - 1) * 4.5, l,
                         fontName="Inter-SemiBold", fontSize=7.4, fillColor=DEEP, textAnchor="middle"))
    y1, y2, y3 = 285, 200, 115
    st(4, y1, "Request\n(any department)", fill=colors.white)
    st(124, y1, "Registered")
    st(244, y1, "Awaiting\nassignment")
    st(364, y1, "Assigned")
    st(364, y2, "Accepted")
    st(244, y2, "In progress")
    st(124, y2, "Waiting: on hold,\nmaterials, isolation…", fill=colors.HexColor("#FFF4E5"), stroke=AMBER)
    st(244, y3, "Awaiting review")
    st(364, y3, "Closed", fill=colors.HexColor("#E7F6EE"), stroke=GREEN)
    st(124, y3, "Reopened")
    st(4, y2, "Awaiting\nclarification", fill=colors.HexColor("#FFF4E5"), stroke=AMBER)
    st(4, y3, "Cancelled", fill=colors.HexColor("#F4F4F4"), stroke=MUTED)
    arrow(d, 96, y1 + 15, 124, y1 + 15, label="triage")
    arrow(d, 216, y1 + 15, 244, y1 + 15, label="assess")
    arrow(d, 336, y1 + 15, 364, y1 + 15, label="assign")
    arrow(d, 410, y1, 410, y2 + h, label="accept")
    arrow(d, 364, y2 + 15, 336, y2 + 15, label="start")
    arrow(d, 244, y2 + 9, 216, y2 + 9)
    arrow(d, 216, y2 + 21, 244, y2 + 21)
    arrow(d, 290, y2, 290, y3 + h, label="submit")
    arrow(d, 336, y3 + 15, 364, y3 + 15, label="verify")
    arrow(d, 364, y3 + 6, 216, y3 + 6)
    d.add(String(290, y3 - 9, "returned for more work → back to Accepted", fontName="Inter", fontSize=6.6,
                 fillColor=MUTED, textAnchor="middle"))
    arrow(d, 124, y1 + 5, 96, y2 + 25)
    d.add(String(160, 76, "Reopened goes back to Assigned or Accepted.  Any open stage can be cancelled "
                 "with a reason.", fontName="Inter", fontSize=6.8, fillColor=MUTED, textAnchor="middle"))
    d.add(String(160, 64, "Time spent waiting (amber) does not count against the deadline.", fontName="Inter",
                 fontSize=6.8, fillColor=MUTED, textAnchor="middle"))
    return d


# ---------------------------------------------------------------------------
# Document
# ---------------------------------------------------------------------------
class Doc(BaseDocTemplate):
    def afterFlowable(self, f):
        if hasattr(f, "_toc"):
            self.notify("TOCEntry", (0, f._toc, self.page))


def cover(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(DEEP)
    canvas.rect(0, 0, A4[0], A4[1], stroke=0, fill=1)
    canvas.setFillColor(MAROON)
    canvas.circle(A4[0] * 0.85, A4[1] * 0.82, 210, stroke=0, fill=1)
    canvas.setFillColor(colors.HexColor("#7A1A22"))
    canvas.circle(A4[0] * 0.1, A4[1] * 0.12, 160, stroke=0, fill=1)
    try:
        canvas.drawImage(f"{REPO}/app/assets/branding/logo.png", 22 * mm, A4[1] - 70 * mm,
                         width=46 * mm, height=30 * mm, preserveAspectRatio=True, mask="auto")
    except Exception:
        pass
    canvas.setFillColor(colors.white)
    canvas.setFont("Inter-ExtraBold", 34)
    canvas.drawString(22 * mm, A4[1] * 0.52, "How the system works")
    canvas.setFont("Inter-SemiBold", 15)
    canvas.setFillColor(ROSE)
    canvas.drawString(22 * mm, A4[1] * 0.52 - 26, "Bravura Electrical Department app")
    canvas.setFont("Inter", 10.5)
    canvas.setFillColor(colors.white)
    y = A4[1] * 0.52 - 60
    for line in ["A full guide: what it does, who does what, how work flows,",
                 "and how it runs, is kept safe and is released."]:
        canvas.drawString(22 * mm, y, line)
        y -= 15
    canvas.setFont("Inter", 9)
    canvas.setFillColor(ROSE)
    canvas.drawString(22 * mm, 22 * mm, "Version as of 8 November 2026  ·  web app and Android app v0.1.x")
    canvas.restoreState()


def page(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINE)
    canvas.line(20 * mm, A4[1] - 14 * mm, A4[0] - 20 * mm, A4[1] - 14 * mm)
    canvas.setFont("Inter-Medium", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(20 * mm, A4[1] - 11.5 * mm, "Bravura Electrical Department · How the system works")
    canvas.drawRightString(A4[0] - 20 * mm, 10 * mm, f"{doc.page}")
    canvas.restoreState()


doc = Doc(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=20 * mm,
          bottomMargin=18 * mm, title="How the system works", author="Bravura Electrical Department",
          subject="Full guide to the Electrical Department app")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
doc.addPageTemplates([PageTemplate(id="cover", frames=[frame], onPage=cover),
                      PageTemplate(id="page", frames=[frame], onPage=page)])

story.append(NextPageTemplate("page"))
story.append(PageBreak())
story.append(Paragraph("Contents", S["h1"]))
toc = TableOfContents()
toc.levelStyles = [S["toc1"]]
toc.dotsMinLevel = 0
story.append(toc)
story.append(PageBreak())

# 1 -------------------------------------------------------------------------
h1("What the system is")
p("The Electrical Department app is the one place where the electrical team runs its work at every "
  "Bravura site (Harare, Kamativi, Manhizi and Selous). It replaces paper job cards, tool issue "
  "forms, store cards, WhatsApp groups and spreadsheets with one app that works on Android phones and "
  "in any web browser.")
h2("What it covers")
table([
    ["Area", "What people do there"],
    ["Job cards", "Report faults, register, assess, assign, do and verify the work, with time, safety "
                  "checks and photos; requests from other departments."],
    ["Tools and equipment", "The tools register, signed issue forms, calibration certificates, repairs, "
                            "who has what; the asset register and planned maintenance."],
    ["Inventory and materials", "Stock on hand, receiving, issuing, counts; material requests, purchases "
                                "and project bills of quantities (BOQ)."],
    ["Projects and planning", "Projects with progress, the calendar of everything due, the weekly "
                              "roster with standby."],
    ["Safety and records", "SOPs and drawings with read-and-sign, daily checklists (rounds), daily "
                           "reports with supervisor approval."],
    ["Communication", "Team and direct chats, voice and video calls, meetings with minutes, "
                      "notifications and personal reminders."],
    ["Management", "Statistics for jobs, tools and inventory; users, roles and permissions; "
                   "activity log; error reports; backups."],
], [42, 128])
h2("Principles it is built on")
bullets([
    "<b>One team, every site.</b> Everyone can see every site, and everyone's role applies at all "
    "sites. The app opens on your home site; the site chip at the top switches, and "
    "<i>All my sites</i> lists every site together.",
    "<b>Works without signal.</b> Most work done on a phone is kept on the phone and sent when there is "
    "signal again. Nothing waiting is lost when the app closes.",
    "<b>Every record has a code</b> (J-, T-, S-, I-, P-, MR-, PO-, R-, M-, TI-, EL-JC-, EL-SR-) that is "
    "never reused, so it can be quoted in chat, on paper and in reports.",
    "<b>Nothing is deleted.</b> Records are archived, and every change is written to the activity log "
    "with who and when.",
    "<b>The server checks everything.</b> The app hides buttons people cannot use, but the database "
    "itself refuses any change a person is not allowed to make.",
])

# 2 -------------------------------------------------------------------------
h1("How it is built")
story.append(KeepTogether([Paragraph("There is one app, written in Flutter, built twice: as an Android app (APK) and as a web app. Both "
  "talk to the same server, Supabase, which holds the data, the files and the rules.", S["body"]), Spacer(1, 6), architecture()]))
story.append(Spacer(1, 6))
table([
    ["Part", "Role", "Notes"],
    ["Flutter app", "Screens on phones and browsers", "Code in <i>app/</i>. Keeps a local database "
                                                      "(drift) for offline use and an outbox of "
                                                      "changes waiting to send."],
    ["Supabase database", "All records and the rules", "PostgreSQL. 39 numbered migrations in "
                                                       "<i>supabase/migrations</i>; every table has "
                                                       "row-level security; changes go through "
                                                       "fn_* functions."],
    ["Supabase Auth", "Sign-in", "Email and password; admins create accounts and reset passwords."],
    ["Supabase Storage", "Files", "Photos, documents, certificates, signatures, chat files, in private "
                                  "buckets, opened with links that expire."],
    ["Scheduled jobs", "Timers on the server", "Escalations every 10 minutes, reminders every minute, "
                                               "tool and checklist reminders, daily report build, "
                                               "standby reminders."],
    ["Edge functions", "Server code", "Push sending, call tokens (LiveKit), user administration."],
    ["Firebase", "Push notifications", "Alerts reach phones even when the app is closed."],
    ["LiveKit Cloud", "Calls", "Voice and video calls inside any chat."],
    ["Vercel", "Web hosting", "electrical-department-lake.vercel.app, deployed on every change to main."],
    ["GitHub", "Code and automation", "Checks every change, deploys the database and the web app, builds "
                                      "the APK, runs the nightly backup and browser tests."],
], [32, 42, 96])

# 3 -------------------------------------------------------------------------
h1("Sites, people, roles and permissions")
h2("Sites and areas")
p("Each site (Harare HRE, Kamativi KAM, Manhizi MAN, Selous SEL) has areas (for example \"Plant – MCC "
  "room\"). Records belong to a site, and record codes count up per site, so Harare and Kamativi can "
  "each have an S-0001. Admins add sites and areas in Settings → Admin → Sites and areas.")
h2("One team")
bullets([
    "Every person's roles apply at <b>every site</b>. A Harare technician can work a Kamativi job card, "
    "do its checklists and sign its SOPs. Alerts come from every site, and everyone is in every site's "
    "group chat.",
    "An admin can still limit a role to one site in Settings → Admin → People, if ever needed.",
    "Viewing permissions (job cards, tools, inventory, documents, equipment, reports, statistics) count "
    "at every site anyway, for anyone who holds them at one site.",
])
h2("Roles")
p("A person has one or more roles. A role is a set of permissions. The table shows what each role "
  "may do by default; admins change it in Settings → Admin → Roles and permissions.")
table([
    ["Role", "What it is for", "Main permissions"],
    ["Technician", "Electricians doing the work", "See and register job cards, work on job cards "
                                                  "assigned to them, do checklists, request materials, "
                                                  "see tools, inventory and documents."],
    ["Supervisor", "Running the team", "Everything on job cards (assess, assign, review, cancel, "
                                       "reopen, escalate), approve material requests and daily "
                                       "reports, manage documents, checklists, projects, the roster "
                                       "and meetings, statistics."],
    ["Storekeeper", "The store and tools", "Issue and receive tools, receive, issue, adjust and count "
                                           "inventory, purchases."],
    ["Department Manager", "Oversight", "See job cards, reopen and escalate, reports, statistics, the "
                                        "activity log."],
    ["Requester", "Other departments", "Send work requests to the electrical department and follow "
                                       "them."],
    ["Admin", "Running the app", "Every permission: people, roles, sites, settings, error reports."],
], [30, 38, 102])
note("The app shows only the buttons a person may use, but the real check is on the server: every "
     "change goes through a database function that checks the permission at that site. A modified app "
     "cannot get round it.")

# 4 -------------------------------------------------------------------------
h1("Finding your way in the app")
table([
    ["Place", "What is there"],
    ["Home", "Greeting, <i>Needs you</i> (critical, overdue, waiting for you), the day's numbers for "
             "the site, shortcuts."],
    ["Jobs", "The job card list with status chips, search and filters; <i>My jobs</i>; statistics."],
    ["Chat", "Group and direct chats, calls, meetings."],
    ["Menu", "Every other screen: Requests, Checklists, Daily report, Equipment &amp; tools, Inventory, "
             "Materials, Projects, Calendar, Roster, Documents, Reminders, Notifications, statistics."],
    ["+ New", "The quick-create sheet: report a fault (job card) or request work, my jobs, today's "
              "report update, a checklist, request materials, issue tools, a reminder."],
    ["Site chip", "At the top: the site you are working in; tap to switch."],
    ["Settings", "Profile, appearance (dark liquid glass by default, light available), notifications, "
                 "<i>Waiting to send</i>, reload, and for admins the Admin section."],
], [30, 140])
p("On a phone the bottom bar scrolls sideways to every screen; on a computer the same screens are in "
  "the menu on the left. Pushed screens have a back arrow at the top left.")

# 5 -------------------------------------------------------------------------
h1("Job cards: from fault to closure")
p("Job cards are the department's one job system. Each has a code like EL-JC-2026-0042, a priority, "
  "a deadline, a team and a full history.")
h2("The stages")
story.append(job_flow())
table([
    ["Stage", "What happens", "Who"],
    ["Request", "Another department sends a request (EL-SR-…) with photos. The electrical team "
                "triages it: registers it as a job card, returns it for more detail, or rejects it.",
     "Requester; triage by technicians and supervisors"],
    ["Registered", "A job card is opened directly (+ New → Report a fault), from a request, from a "
                   "failed checklist item, from planned maintenance or as a follow-up.",
     "Anyone with register permission"],
    ["Assess", "The supervisor checks the job is valid, sets type, severity, safety risk and priority, "
               "or asks the reporter for clarification.", "Supervisor"],
    ["Assign", "A responsible person and a team are set; they are notified.", "Supervisor"],
    ["Accept and start", "The technician accepts, does the safety check (when required), and starts the "
                         "work timer.", "The assigned technician"],
    ["Work", "Work-log entries (diagnosis, actions, readings), photos and files, tools and materials "
             "used, comments with @mentions. Work can be paused for a reason: on hold, waiting for "
             "materials, isolation, a specialist or production clearance.", "The team"],
    ["Submit", "The technician submits the work for review with a summary.", "The responsible person"],
    ["Verify", "The reviewer approves (closes it), approves with a follow-up job card, returns it for "
               "more work, or asks a question.", "Supervisor (not the same person, unless "
                                                 "self-approval is allowed)"],
    ["Closed", "Closure freezes the metrics: response time, working time, waiting time, met or missed "
               "deadline. A closed job card can be reopened with a reason.", "—"],
], [26, 104, 40])
h2("Priorities and deadlines")
table([
    ["Priority", "Meaning", "Respond within", "Finish within"],
    ["P1 Emergency", "Immediate safety hazard, critical supply failure", "15 minutes", "4 hours"],
    ["P2 High", "Significant failure, production affected", "1 hour", "24 hours"],
    ["P3 Medium", "Non-critical fault, limited impact", "4 hours", "3 days"],
    ["P4 Low", "Minor repairs, inspections, improvements", "1 day", "14 days"],
], [28, 82, 30, 30])
p("Admins can change these targets in Settings → Admin → Job card settings. Time spent in a waiting "
  "state moves the deadline, so a job is not counted late while it waits for materials.")
h2("Escalation")
p("Every 10 minutes the server checks open job cards against nine escalation rules (for example: a "
  "critical job not yet assigned, a job close to or past its deadline, a job on hold too long) and "
  "notifies the right people once per rule and deadline. Supervisors and managers can also escalate "
  "a job card by hand.")
h2("Linked to everything else")
bullets([
    "<b>Tools</b> on a job card: add the tools the job needs, see who has each, issue them on a form.",
    "<b>Documents</b>: attach the SOP or drawing for the job.",
    "<b>Materials</b>: request materials for the job; stock issued to it is listed.",
    "<b>Projects</b>: a job card can belong to a project, whose progress counts it.",
    "<b>Chat</b>: type # to share a job card in a chat as a card that opens it.",
])

# 6 -------------------------------------------------------------------------
h1("Tools and equipment")
h2("The tools register")
p("Every tool has a T- code, kind, serial number, condition (good, needs repair, damaged, lost) and, "
  "for meters and testers, a calibration due date. The register shows what is in the store, out, "
  "overdue back and due for calibration.")
h2("Issuing tools on a form")
bullets([
    "The store issues one or more tools to a person (an app user or anyone, for example a contractor) "
    "on a <b>tool issue form</b> (TI-), with company, team lead, place, return date, the condition of "
    "each tool, and <b>three signatures</b>: issuer, recipient and team lead.",
    "Taking tools back records the condition of each and three signatures again; part of a form can "
    "come back at a time. The form prints as a PDF laid out like the company's paper form.",
    "Tools already out, damaged, lost or with expired calibration cannot be issued.",
])
h2("Repairs, calibration, who has what")
bullets([
    "A tool returned <b>damaged or needing repair</b> opens a repair job card automatically; when that "
    "job card is closed the tool is back to good and the store is told.",
    "<b>Calibration certificates</b> (PDF or photo) are uploaded with their dates; the newest sets the "
    "due date. Reminders go out 7 days before.",
    "<b>Who has what</b> lists everyone holding tools now, with their company and what is overdue.",
    "<b>Tool stats</b>: losses, late returns, damage with its repair job card, calibration, and a "
    "summary per person, for 7 days to a year, one site or all.",
    "Daily at 07:15 Harare the server reminds holders of overdue tools and the store of calibration "
    "due.",
])
h2("Equipment and planned maintenance")
p("The asset register lists plant and equipment with tag, category, location, ratings, criticality "
  "and status. <b>Planned maintenance</b> plans (daily, weekly, monthly) raise preventive job cards "
  "automatically on their dates.")

# 7 -------------------------------------------------------------------------
h1("Inventory")
p("Inventory (formerly the store) holds electrical stock per site. Each item has an I- code, unit, "
  "category, bin and an <i>alert below</i> level. Stock on hand only changes through movements, so it "
  "always equals the sum of its history and never goes below zero.")
table([
    ["Movement", "Who", "What it does"],
    ["Receive", "Store", "Stock in (a delivery), with a supplier or delivery note."],
    ["Issue", "Store", "Stock out to a job card, a project or a person; refused if not enough."],
    ["Take back", "Store", "Unused stock returned from a job card or a person."],
    ["Adjust", "Store", "A correction with a required reason (damaged, found, written off)."],
    ["Count", "Store", "Count the shelves by bin, offline too; a count in progress is kept if you leave. "
                       "Only items that differ are corrected, as of when they were counted (later issues "
                       "stay). Past counts lists every count and its corrections."],
], [26, 22, 122])
bullets([
    "When an item falls below its level, the store and supervisors are alerted.",
    "The list is saved on the phone; without signal it shows the saved stock with the time it was "
    "saved. Movements made offline are sent later.",
    "<b>Import from Excel</b>: load items with opening stock from a spreadsheet.",
    "<b>Inventory stats</b>: what was used most, stock per project, job cards using the most, "
    "corrections, what is low.",
])

# 8 -------------------------------------------------------------------------
h1("Materials, purchases and bills of quantities")
h2("Material requests (MR-)")
bullets([
    "Anyone in the team requests materials for a job card, a project or the site: items from "
    "inventory, or things not stocked, typed in.",
    "A supervisor approves, or rejects with a reason. The requester is told either way.",
    "The store <b>issues</b> what is in inventory (to the request's job card and project) and "
    "<b>orders</b> what is missing.",
])
h2("Purchases (PO-)")
bullets([
    "A purchase has a supplier, the company PO number, expected date, lines and prices. It can be "
    "filled in from a material request in one tap.",
    "Status: to order → ordered → delivered (or cancelled). <b>Receive delivery</b> puts items into "
    "inventory; something not stocked counts as handed over on its request. Whoever asked is told it "
    "has arrived.",
    "Prices are seen only by the store and supervisors.",
])
h2("Bill of quantities (BOQ)")
p("A project's BOQ is imported from Excel (or pasted). Each line shows how much was issued, is "
  "requested, is on order and is in inventory, and what is still short. <b>Request the shortfall</b> "
  "turns everything missing into one material request.")

# 9 -------------------------------------------------------------------------
h1("Projects, calendar and roster")
h2("Projects (P-)")
p("A project groups job cards, materials and a BOQ, with a target date, a leader and a team. Its "
  "progress ring shows job cards closed out of all (not cancelled). Team members are notified when "
  "added.")
h2("Calendar")
p("A month view with a coloured dot for each kind of thing due: job cards by their deadline, "
  "meetings, tools due back, calibration, planned maintenance, project deadlines, your own shifts and "
  "standby, and your reminders. Tap a day for its list; tap an entry to open it.")
h2("Roster and standby")
bullets([
    "Supervisors set each person's day for the week: day, night, off or leave, plus standby (on call).",
    "Publishing the week tells everyone on it. People on standby get a reminder at 16:00 the day before.",
    "Everyone sees <i>My shifts</i> at the top of the roster.",
])

# 10 ------------------------------------------------------------------------
h1("Documents, checklists and daily reports")
h2("Documents (S-)")
bullets([
    "SOPs, drawings, manuals and forms per site, in folders, as a grid or list, with filters (to sign, "
    "recent, added by me, type) and coloured file-type badges.",
    "Each document keeps every version. A document marked <i>everyone must read and sign</i> asks "
    "people to sign the current version; a new version asks again. Supervisors see who has signed.",
    "Upload several files at once (or drop them onto the page on a PC); drag a document onto a folder "
    "to file it; share in a chat; copy a 7-day link for someone without the app; move, edit, archive.",
])
h2("Checklists (daily rounds)")
bullets([
    "Supervisors build templates per area: tick items, readings with limits, text, required photos; "
    "daily, weekly or monthly.",
    "Technicians do the round on the phone, even offline. A failed tick or a reading out of limits "
    "<b>raises a job card</b>.",
    "At 15:00 the assignee is reminded of rounds due today; at 19:00 supervisors hear what was missed.",
])
h2("Daily reports (R-)")
bullets([
    "Each site has a daily report built automatically (19:10 every night): job cards opened and closed, "
    "checklists done and missed, tools out. Everyone adds their own update with photos.",
    "A supervisor approves the report with a comment; it exports as a PDF.",
    "The <b>reports archive</b> lists every report and searches through what people wrote.",
])

# 11 ------------------------------------------------------------------------
h1("Chat, calls and meetings")
bullets([
    "<b>Chats</b>: every site has a group, the department has one, and anyone can start a direct chat. "
    "Messages, photos, voice notes, files, replies, reactions, @mentions, pins; documents and records "
    "(type #) shared as cards that open them. Messages sent offline go when there is signal.",
    "<b>Calls</b>: voice or video in any chat, with screen sharing and speaker on phones; incoming calls "
    "ring the phone.",
    "<b>Meetings (M-)</b>: scheduled from a group chat with an agenda; everyone in the chat is invited and "
    "reminded 15 minutes before, and joins through the chat's call. Minutes hold a summary, decisions "
    "and actions with owners and dates. Automatic transcription waits for its service key.",
])

# 12 ------------------------------------------------------------------------
h1("Notifications and reminders")
bullets([
    "Notifications appear in the app (the bell) and as push alerts on phones and browsers that allow "
    "them. Each opens the record it is about.",
    "Examples: a job card assigned to you, a mention, a job going overdue or escalated, something to "
    "approve, low stock, a meeting starting, a roster published, a delivery arrived, tools overdue.",
    "<b>Personal reminders</b>: \"Remind me\" on a job card or tool, or from + New: in 1 hour, later "
    "today, tomorrow 08:00 or any time. They work offline and arrive as a notification.",
])

# 13 ------------------------------------------------------------------------
h1("Statistics")
table([
    ["Screen", "Shows"],
    ["Job statistics", "Trends, job cards by priority, type, area, equipment and technician, overdue "
                       "ageing, response and closure times."],
    ["Tool stats", "Losses, late returns, damage and repairs, calibration, per person and company."],
    ["Inventory stats", "Most used items, stock per project, job cards using the most stock, "
                        "corrections, low stock, open requests and purchases, project status."],
    ["Home", "The day's open, critical, overdue and closed-today counts, and what needs you."],
], [36, 134])
p("Each works for one site or <i>All my sites</i>, over a chosen period.")

# 14 ------------------------------------------------------------------------
h1("Working without signal")
p("Mine sites often have weak or no signal, so the app is built to keep working.")
h2("What works offline")
bullets([
    "Viewing what was last loaded: job cards, tools, equipment, people, inventory, checklists.",
    "Doing work: job card notes, work-log entries and photos, checklists, daily report updates, tool "
    "issue forms and returns, inventory movements and counts, material requests, projects, rosters, "
    "document uploads, chat messages, reminders.",
])
h2("How changes reach the server")
bullets([
    "Each change goes into the phone's <b>outbox</b> with its own id, files first, then changes in the "
    "order they were made. The same change sent twice is saved once.",
    "No signal is never a failure: the app tries again after 30 seconds, then waits longer each time "
    "(up to 10 minutes), and goes straight away when the app comes back to the foreground or someone "
    "taps <i>Send now</i>.",
    "Only the server refusing a change marks it <i>not saved</i>, for example a note on a job card that "
    "someone else cancelled meanwhile. It then shows in the banner and in Settings → <i>Waiting to send</i> "
    "with <b>Try again</b> and <b>Discard</b>.",
    "A change whose file the server refused waits until the file is tried again or discarded, so no "
    "record points at a missing photo.",
    "<b>Signing out</b> with work not yet sent asks first: wait, see what is waiting, or sign out and "
    "delete it. Nothing unsent is deleted silently.",
    "Up to 300 MB of files can wait on a phone. Status changes and work timers need signal, so the "
    "server's times stay true.",
])

# 15 ------------------------------------------------------------------------
h1("Administration")
table([
    ["Screen (Settings → Admin)", "What admins do"],
    ["People", "Create accounts, activate or deactivate, roles (at all sites or one), reset passwords."],
    ["Roles and permissions", "Switch what each role may do. The Admin role always keeps user "
                              "management."],
    ["Sites and areas", "Add and rename sites and their areas."],
    ["Job card settings", "Priorities and targets, numbering, categories, departments, escalation rules "
                          "and contacts, safety checklist items and when the safety check is required."],
    ["Activity log", "Every change to every record: who, what, when."],
    ["App errors", "Errors that happened on people's phones and browsers, grouped, with how often, for "
                   "how many people, the app version and the screen; mark fixed."],
], [44, 126])
p("Imports from Excel (inventory items, tools, BOQs) accept .xlsx or CSV files whose first row names "
  "the columns; the app works out which column is which.")

# 16 ------------------------------------------------------------------------
h1("Keeping the data safe")
bullets([
    "<b>Access</b>: private by default. Every table has row-level security; every change goes through a "
    "function that checks the person's permission at that site. Files open only through links that "
    "expire.",
    "<b>History</b>: nothing is deleted; records are archived and every change is in the activity log.",
    "<b>Backups</b>: every night at 00:20 Harare the live database is copied, restored into a test "
    "database and compared table by table (so the backup is known to work), encrypted with a passphrase "
    "and kept 90 days. Photos and document files in storage are not in this backup.",
    "<b>Secrets</b> (keys, passwords) live only in GitHub and Supabase settings, never in the code.",
    "<b>Privacy</b>: the privacy policy is published at /privacy.html on the web app.",
])

# 17 ------------------------------------------------------------------------
h1("How changes are made and released")
table([
    ["Step", "What happens"],
    ["1. A change", "Code is changed in the repository (GitHub). Database changes are a new numbered "
                    "migration with a test; old migrations are never edited."],
    ["2. Checks", "GitHub checks every push: code format, analysis, app tests (79), and every database "
                  "test against a throwaway copy of the database (659 checks)."],
    ["3. Deploy", "On main: the migrations are applied to the live database, and the web app is "
                  "built and published on Vercel within minutes."],
    ["4. Android", "Every push builds an APK. A release (run by hand with a version like v0.1.3) builds "
                   "the signed APK and the Play Store bundle, attaches them to a GitHub release and "
                   "sends them to testers through Firebase App Distribution."],
    ["5. Nightly", "Browser tests run the main flows every night; the backup runs at 00:20."],
], [28, 142])
p("Phones get new features only with a new APK release; the web app updates on every deploy.")

# 18 ------------------------------------------------------------------------
h1("Record codes")
table([
    ["Code", "Record", "Code", "Record"],
    ["EL-JC-YYYY-NNNN", "Job card", "EL-SR-YYYY-NNNN", "Request from another department"],
    ["T-", "Tool", "TI-", "Tool issue form"],
    ["I-", "Inventory item", "MR-", "Material request"],
    ["PO-", "Purchase", "P-", "Project"],
    ["S-", "Document (SOP, drawing…)", "R-", "Daily report"],
    ["M-", "Meeting", "J-", "Old jobs board job (read only)"],
], [34, 51, 34, 51])

# 19 ------------------------------------------------------------------------
h1("Still waiting on people")
p("Everything planned has been built. These steps need a person with a phone, an account or a "
  "secret:")
table([
    ["Item", "Why it matters"],
    ["Release v0.1.4 to phones", "Phones are on 27 October's version and miss three weeks of work, "
                                 "including the offline and sign-out fixes."],
    ["BACKUP_PASSPHRASE secret in GitHub", "Without it the nightly backup stops rather than keep an "
                                           "unencrypted copy."],
    ["Firebase App Distribution role", "So testers receive new APKs automatically."],
    ["Transcription key (Groq)", "For automatic meeting transcription."],
    ["Phone testing", "Run docs/offline-test-plan.md on an Android phone."],
    ["Play Store account (optional)", "A one-time 25 US dollars; the bundle, policy and listing are "
                                      "ready."],
], [60, 110])
p("More detail for developers is in API.md (every table, function and rule), CHANGELOG.md (what "
  "changed when) and docs/ in the repository.")

doc.multiBuild(story)
print("built", OUT)
