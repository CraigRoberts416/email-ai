# **Section 1: Product Overview**

## **Section 1: Product Overview**

### **Product Type**

Consumer **email application (email client)**

Decision Inbox connects to existing email providers and reimagines how users **understand and process email**.

It does not replace email infrastructure.

Instead, it restructures the inbox into a system that makes email **faster to understand, safer to use, and easier to act on**.

Supported providers include:

* Gmail

* Outlook

* Yahoo Mail

---

# **Vision**

Email should immediately communicate what matters.

Users should not have to open messages to figure out:

* what an email is about

* whether it requires action

* whether it is legitimate

Decision Inbox transforms the inbox from a list of messages into a system that helps users quickly determine:

What this email is about

Whether it requires action

Whether it is safe

What they should do next

The product focuses on three outcomes:

Clarity

Protection

Control

---

# **Core Insight**

Email was designed for **sending messages**, not for **interpreting meaning**.

Traditional email apps show metadata such as:

Sender

Subject

Preview text

Users must read the message to understand:

What the sender wants

Whether action is required

Whether the email is legitimate

As inboxes have become filled with:

* marketing messages

* receipts and updates

* surveys

* phishing attempts

the burden of interpretation has shifted entirely onto the user.

Decision Inbox uses AI to surface **meaning directly in the inbox**.

---

# **Product Concept**

Decision Inbox organizes email as a **feed of conversation cards**.

Each card represents a conversation thread and surfaces the meaning of the latest message.

Cards expose the most important information immediately:

Sender

Intent

Quote

Status

Users can act on most emails directly from the card without opening the thread.

Primary actions include:

Reply

Discuss

Forward

Save

Archive

This allows users to process their inbox quickly.

---

# **The Card Model**

Each conversation appears as a **card** in the feed.

Cards contain three layers:

Header

Carousel body

Action row

---

## **Header**

The header identifies the sender and key controls.

Structure:

Sender      Relationship OR Unsubscribe      •••

Examples:

Bob Chen        Friend

Delta Airlines  Company

Nike            Unsubscribe

For marketing emails, **Unsubscribe replaces the relationship signal** to make the most useful action immediately accessible.

---

## **Carousel Body**

The center of the card is a **carousel** that allows users to preview the email without opening it.

Carousel structure:

1\. Intent card

2\. Attachment preview(s) (if present)

3\. Open full email card

The carousel always follows this order.

---

### **Intent Card**

The first carousel page always contains the **intent summary**.

It includes:

Intent

Quote

Status

Example:

Schedule intro call

“Would love to schedule a quick intro next week.”

● Waiting on you

This card is designed to give users enough information to decide how to handle the email.

---

### **Attachment Previews**

If the email contains attachments, additional carousel pages appear showing previews.

Examples include:

* images

* PDFs

* documents

* tickets

* receipts

This allows users to quickly inspect attachments without opening the full thread.

---

### **Open Full Email**

The final carousel page allows users to open the full conversation thread.

Open full email

This ensures every card has a consistent final action for deeper reading.

---

## **Action Row**

Below the carousel are the primary actions.

These actions are **consistent across all cards**.

Reply

Discuss

Forward

Save

Archive

Maintaining a consistent action set ensures predictable interaction patterns.

Additional actions are available in the overflow menu.

---

# **AI Thinking Layer**

Decision Inbox includes an AI assistant that helps users interpret emails.

Users can open a **discussion interface** to talk with the AI about a conversation.

The discussion interface appears as a bottom-sheet conversation similar to comment interactions in Instagram.

Users can ask questions such as:

What does this email mean?

What is the sender asking for?

Is this email legitimate?

What should I say in response?

Summarize this conversation

AI helps users understand messages and think through responses.

AI does not send emails automatically.

Users remain fully in control of communication.

---

# **Inbox Feed**

The inbox is presented as a **feed of conversation cards**.

Each conversation appears once in the feed.

When a new message arrives in the conversation:

The card updates

The card moves to the top

Intent and quote update

Status may change

Users can choose between two feed modes.

### **Chronological Feed**

Conversations are ordered by most recent activity.

### **Relevance Feed**

AI ranks conversations based on signals such as:

Action required

Relationship strength

Conversation recency

Risk signals

Promotion classification

---

# **Protection System**

Decision Inbox actively helps users avoid scams and unwanted messages.

The system analyzes emails for signals such as:

Domain mismatch

Suspicious links

Impersonation patterns

Urgent financial requests

Potentially dangerous messages are labeled clearly.

Example:

⚠ Potential scam

Marketing emails are detected and surfaced with unsubscribe controls.

---

# **Subscription Control**

Marketing emails are classified automatically.

When a conversation is identified as promotional, the card displays:

Unsubscribe

Users can remove unwanted messages quickly.

Two mechanisms exist:

### **Local unsubscribe**

The sender is hidden from the feed within the app.

### **Future agent unsubscribe**

AI may attempt to complete unsubscribe flows automatically with the sender.

---

# **Product in One Sentence**

Decision Inbox is an email app that helps users quickly understand their inbox, avoid scams, and control unwanted email.

---

# **Product in Three Words**

Clarity

Protection

Control

# **Section 2: Product Principles**

## **Section 2: Product Principles**

This section defines the **core principles that guide the product**.

They act as guardrails for product, design, and engineering decisions.

If a new feature conflicts with these principles, the principle takes priority.

These principles ensure the product remains focused on **clarity, safety, and control**.

---

# **2.1 Meaning Before Metadata**

Traditional email interfaces prioritize metadata:

Sender

Subject

Preview text

This forces users to interpret messages themselves.

Decision Inbox prioritizes **meaning instead of metadata**.

Each conversation card surfaces:

Intent

Quote

Status

Sender

The goal is for users to understand **what the message means** without opening the email.

Intent answers:

What is this about?

Status answers:

Do I need to do something?

Quote answers:

Is this interpretation accurate?

Meaning should always be visible before the user reads the full message.

---

# **2.2 Conversations Over Messages**

The inbox should focus on **conversations**, not individual emails.

Traditional email systems treat each message as a separate entry.

This creates clutter when conversations contain multiple messages.

Decision Inbox groups messages into **conversation threads**, and each thread appears as a single card in the feed.

When a new email arrives in a thread:

The card updates

The card moves to the top of the feed

Intent and quote update

Status may change

Users process conversations rather than scanning lists of messages.

---

# **2.3 Fast Understanding**

The product is designed for **rapid comprehension**.

Users should be able to answer three questions immediately:

Who is this from?

What is this about?

What should I do?

Every element of the card exists to support these decisions.

The **first carousel card (Intent card)** must provide enough information for users to triage the email.

Additional carousel pages provide depth but should not be required for understanding.

---

# **2.4 Consistency Creates Speed**

The interface must remain predictable.

All cards share the same structure:

Header

Carousel body

Action row

All cards contain the same primary actions:

Reply

Discuss

Forward

Save

Archive

Actions never move or change based on email type.

Predictability allows users to build muscle memory and process email faster.

---

# **2.5 AI Assists Thinking, Not Communication**

Artificial intelligence is used to help users **understand and reason about email**.

AI can:

Interpret intent

Explain emails

Summarize conversations

Identify scams

Help brainstorm responses

AI cannot:

Send emails automatically

Respond to other people

Communicate with other AI systems

Users remain responsible for communication.

The system is designed to **support thinking**, not replace human interaction.

---

# **2.6 Trust Through Evidence**

AI interpretations must always be verifiable.

Every AI-generated intent is paired with a **quote from the email**.

Example:

Intent

Schedule intro call

Quote

"Would love to schedule a quick intro next week."

This ensures users can confirm that the interpretation reflects the original message.

Trust is maintained through **transparency and evidence**.

---

# **2.7 Protection Before Productivity**

The inbox should actively protect users from harmful messages.

Decision Inbox prioritizes:

Scam detection

Risk signals

Sender verification

Subscription control

Potentially dangerous emails are clearly labeled.

Marketing emails expose unsubscribe controls immediately.

Safety is treated as a **core feature**, not an afterthought.

---

# **2.8 Control Over Automation**

Automation must never remove user control.

Users can always:

Override AI interpretations

Open the full email

Block or hide senders

Report scams

Manage subscriptions

Automation should simplify decisions without removing user authority.

---

# **2.9 Calm Interface**

Email overload is partly a visual problem.

The interface should remain:

Minimal

Readable

Predictable

Cards expose only the information necessary to make decisions.

Advanced features such as AI discussion appear only when the user explicitly chooses to engage with them.

This prevents unnecessary cognitive load.

---

# **2.10 Focus on Resolution**

The goal of the inbox is not endless consumption.

The goal is **resolution**.

Users should feel that they can process their inbox quickly and reach a clear endpoint.

When the feed ends, the product reinforces completion.

Example:

Inbox Zero

You're caught up

The system should encourage users to leave their inbox and return to the rest of their day.

---

# **Section 2 Summary**

The product is guided by ten principles:

Meaning before metadata

Conversations over messages

Fast understanding

Consistency creates speed

AI assists thinking, not communication

Trust through evidence

Protection before productivity

Control over automation

Calm interface

Focus on resolution

These principles ensure the product remains focused on **clarity, safety, and decisive interaction with email**.

# **Section 3: User Personas**

## **Section 3: User Personas**

This section defines the **users the product is built for**.

Personas help ensure product decisions remain grounded in real behaviors rather than hypothetical use cases.

Decision Inbox is designed primarily for **everyday consumer email users**, not enterprise workflow users.

The personas below represent the most common patterns of inbox usage.

---

# **3.1 Primary Persona**

## **The Overloaded Consumer**

### **Description**

The Overloaded Consumer uses email primarily to manage everyday life.

Their inbox acts as a central hub for:

* purchases

* services

* accounts

* travel

* healthcare

* occasional personal communication

They are not trying to optimize productivity workflows.

They simply want their inbox to **feel manageable and trustworthy**.

---

### **Typical Inbox Composition**

Their inbox is a mixture of:

Receipts

Shipping notifications

Account updates

Promotional emails

Newsletters

Survey requests

Personal messages

Occasional service alerts

A large portion of the inbox is **marketing and automated updates**.

Important emails often appear among these messages.

---

### **Core Frustrations**

The Overloaded Consumer experiences several recurring problems:

Too many promotional emails

Difficulty identifying important messages

Constant unsubscribe requests

Fear of phishing or scam emails

Time spent opening emails just to understand them

They often feel that their inbox has become **noisy and difficult to trust**.

---

### **Goals**

Their primary goals are:

Quickly understand their inbox

Avoid scams

Remove unwanted emails

Respond to important messages

Feel confident they didn't miss anything important

They want email to feel **clear, safe, and manageable**.

---

### **Behavior Patterns**

Common behaviors include:

* scanning subject lines quickly

* ignoring most promotional messages

* deleting many emails without opening them

* manually unsubscribing from marketing lists

* searching the inbox for important past emails

They often hesitate when encountering unfamiliar senders.

---

# **3.2 Secondary Persona**

## **The Busy Professional**

### **Description**

The Busy Professional uses email for both **professional and personal communication**.

Their inbox often contains active conversations requiring responses.

They need to quickly determine:

Which emails require action

Which conversations are ongoing

Which messages can be ignored

---

### **Typical Inbox Composition**

Recruiter messages

Meeting coordination

Client communication

Travel confirmations

Service updates

Receipts

Promotional emails

Multiple conversations may be active simultaneously.

---

### **Core Frustrations**

Common frustrations include:

Important emails buried under promotions

Difficulty tracking conversation threads

Too much time spent reading emails

Unclear next steps in email discussions

They want to process email **quickly and confidently**.

---

### **Goals**

Respond quickly to important conversations

Avoid missing opportunities

Understand conversations without rereading emails

Reduce time spent in the inbox

---

# **3.3 Safety-Focused Persona**

## **The Scam-Conscious User**

### **Description**

Some users are particularly concerned about phishing and scam emails.

This group often includes:

* older adults

* less technically experienced users

* users managing financial or medical communication through email

They worry about accidentally clicking a malicious link or responding to a fraudulent email.

---

### **Core Frustrations**

Difficulty identifying legitimate senders

Fear of scams

Uncertainty about suspicious messages

Confusion about phishing signals

Modern phishing emails often appear legitimate and professional.

---

### **Goals**

Know whether an email is safe

Avoid scams

Feel confident interacting with their inbox

This persona benefits significantly from:

Clear risk signals

Intent explanations

AI assistance

---

# **3.4 Shared Jobs-to-be-Done**

Across personas, users hire email to perform several functional jobs.

---

### **Functional Jobs**

Understand what emails are about

Identify which messages require action

Respond to conversations

Remove unwanted messages

Avoid scams

---

### **Emotional Jobs**

Users also want to feel:

Confident they didn't miss something important

In control of their inbox

Protected from scams

Less overwhelmed by email

---

# **3.5 Product Fit**

Decision Inbox is best suited for users who want:

Faster inbox comprehension

Less promotional email noise

Better scam protection

Clear conversation tracking

The product succeeds when users can process their inbox **without opening most emails**.

---

# **Section 3 Summary**

Decision Inbox is designed primarily for:

Consumers overwhelmed by marketing email

Users concerned about phishing and scams

People who want to understand their inbox quickly

The product prioritizes **clarity, safety, and speed of understanding**.

---

Next would be **Section 4: Problem Definition**, where we document the key problems this product solves and the behaviors that create them.

# **Section 4: Problem Definition**

## **Section 4: Problem Definition**

This section defines the **core problems the product is designed to solve**.

These problems are grounded in how consumers actually experience email today.

Most email clients were designed when inboxes primarily contained **person-to-person communication**.

Today, inboxes contain a mixture of:

Marketing

Receipts

Account notifications

Automated updates

Surveys

Personal messages

Phishing attempts

As a result, the inbox has become **noisy, confusing, and difficult to trust**.

Decision Inbox focuses on solving four primary problems:

Subscription overload

Scams and phishing

Inbox clutter

High cognitive effort to interpret emails

---

# **4.1 Subscription Overload**

### **Description**

Consumers receive a large volume of marketing emails due to:

* online purchases

* app signups

* account creation

* loyalty programs

* newsletter subscriptions

Even when users initially consent to these messages, they often accumulate over time.

Many inboxes contain **dozens of marketing emails per week**.

Examples include:

Store promotions

Seasonal sales

Product launches

Newsletter updates

Survey requests

---

### **Current Solutions**

Users attempt to manage this through:

Ignoring emails

Deleting promotional messages

Manually unsubscribing

Creating filters

However, these solutions are inconsistent and time-consuming.

Many unsubscribe flows require:

* opening the email

* scrolling to the bottom

* navigating to an external webpage

* confirming unsubscribe

Some companies also continue sending messages after unsubscribe attempts.

---

### **User Impact**

Subscription overload creates several problems:

Important emails get buried

Inbox scanning takes longer

Users lose trust in email as a communication channel

Many users feel their inbox has become a **junk drawer of marketing content**.

---

# **4.2 Scams and Phishing**

### **Description**

Email scams have become significantly more sophisticated.

Modern phishing emails frequently impersonate:

Banks

Delivery services

Government agencies

Streaming platforms

Online retailers

Unlike older scams, these messages often appear legitimate.

They may include:

* realistic branding

* convincing language

* professional formatting

---

### **Current Detection Methods**

Users try to detect scams by examining:

Sender email address

Suspicious language

Unexpected links

Urgent requests

However, these signals are becoming harder to interpret.

Many phishing emails are now designed to look authentic.

---

### **User Impact**

This creates several problems:

Users hesitate to trust unfamiliar emails

Users fear clicking links

Users worry about accidentally responding to scams

Some users avoid interacting with legitimate emails due to this uncertainty.

---

# **4.3 Inbox Clutter**

### **Description**

Most consumer inboxes contain a mixture of unrelated message types.

Examples include:

Receipts

Shipping notifications

Account updates

Promotional emails

Newsletters

Personal messages

Traditional inboxes present these messages in a chronological list.

This forces users to repeatedly scan the inbox to determine:

Which messages matter

Which messages require action

Which messages can be ignored

---

### **Current Behavior**

Users typically process email by:

* scanning subject lines

* opening messages to understand them

* deleting or archiving messages

Many emails are opened simply to determine their purpose.

---

### **User Impact**

Inbox clutter leads to:

Slower inbox processing

Missed important messages

Inbox fatigue

Users often describe their inbox as **overwhelming or disorganized**.

---

# **4.4 Cognitive Effort**

### **Description**

Traditional email systems expose metadata rather than meaning.

Users must interpret each message to understand:

What the sender wants

Whether action is required

Whether the email is legitimate

This requires repeated context switching.

---

### **Example Scenario**

A typical inbox might show:

Delta Airlines

Your trip update

Nike

Don't miss this sale

John Smith

Quick question

Users must open these emails to determine:

* whether they require action

* whether they are important

* whether they can be ignored

---

### **User Impact**

This interpretation process creates:

Decision fatigue

Time spent reading unnecessary emails

Difficulty prioritizing conversations

Even small inboxes can feel mentally taxing to process.

---

# **4.5 Loss of Trust in the Inbox**

### **Description**

As marketing messages increase and phishing attacks become more sophisticated, many users no longer fully trust their inbox.

Users are often unsure whether a message is:

Legitimate

Important

Safe to interact with

---

### **Current Behavior**

Users often respond by:

Ignoring unfamiliar emails

Searching for sender information online

Avoiding links in emails

This reduces the usefulness of email as a communication tool.

---

# **4.6 Problem Summary**

The modern inbox suffers from four major issues:

Subscription overload

Scam and phishing risk

Inbox clutter

High cognitive effort

Together, these problems create an inbox experience that feels:

Noisy

Untrustworthy

Time-consuming

Overwhelming

Decision Inbox aims to restore email as a system that provides:

Clarity

Protection

Control

by helping users quickly understand their inbox and safely manage incoming communication.

---

Next is **Section 5: Product Scope**, where we define exactly what the product includes, what it intentionally excludes, and the boundaries of the system.

# **Section 5: Product Scope**

## **Section 5: Product Scope**

This section defines **what the product includes, what it does not include, and the boundaries of the system**.

Clear scope ensures the product remains focused on solving the core problems identified earlier:

Subscription overload

Scams and phishing

Inbox clutter

High cognitive effort to interpret email

Decision Inbox focuses specifically on **improving how users understand and manage incoming email**.

---

# **5.1 Product Type**

Decision Inbox is an **email client**.

It connects to existing email providers and restructures the inbox experience.

Supported providers include:

* Gmail

* Outlook

* Yahoo Mail

The product does **not replace the underlying email infrastructure**.

Instead, it:

Syncs emails

Interprets them

Presents them in a new interface

---

# **5.2 Core Product Capabilities**

The product includes five major capability areas.

Inbox interpretation

Conversation feed

Card-based email interaction

Protection systems

AI discussion

---

# **5.3 Inbox Interpretation**

Decision Inbox analyzes incoming emails to extract meaning and signals.

For each conversation the system generates:

Intent

Quote

Status

Risk indicators

Subscription classification

These signals power the conversation card interface.

The goal is to allow users to **understand the purpose of emails without opening them**.

---

# **5.4 Conversation Feed**

The inbox is presented as a **feed of conversation cards**.

Each conversation thread appears once in the feed.

When a new message arrives:

The card updates

The card moves to the top

Intent and quote update

Status may change

Users can choose between two feed modes.

### **Chronological Feed**

Cards are ordered by most recent activity.

### **Relevance Feed**

AI ranks conversations based on signals such as:

Action required

Relationship strength

Conversation recency

Risk signals

Promotion classification

---

# **5.5 Card-Based Email Interaction**

Emails are managed primarily through the **conversation card interface**.

Each card contains:

Header

Carousel body

Action row

---

### **Header**

Sender     Relationship OR Unsubscribe     •••

Marketing emails replace the relationship label with **Unsubscribe**.

---

### **Carousel Body**

The carousel allows users to preview the email without opening the thread.

Structure:

1\. Intent card

2\. Attachment preview(s)

3\. Open full email

The **intent card** contains:

Intent

Quote

Status

Attachment previews allow quick inspection of files such as:

Images

PDFs

Documents

Tickets

Receipts

The final carousel item always allows users to open the full thread.

---

### **Action Row**

Primary actions appear at the bottom of every card.

Reply

Discuss

Forward

Save

Archive

These actions remain identical across all cards.

Additional actions appear in the overflow menu.

---

# **5.6 Protection Systems**

Decision Inbox includes built-in systems to protect users from unwanted or harmful email.

These systems include:

Scam detection

Risk status indicators

Sender reputation signals

Subscription classification

Suspicious emails receive a risk label such as:

⚠ Potential scam

Marketing emails surface unsubscribe controls.

Users can also:

Block senders

Hide senders

Report scams

---

# **5.7 AI Discussion System**

Users can open an AI discussion interface attached to any conversation.

The discussion interface allows users to:

Ask what an email means

Clarify what the sender wants

Determine if an email is legitimate

Summarize conversations

Think through a reply

The AI discussion appears as a **bottom sheet conversation interface** similar to comment interactions in Instagram.

AI assists users in **interpreting and reasoning about emails**.

AI does not send emails automatically.

---

# **5.8 Subscription Control**

The product helps users remove unwanted promotional email.

Marketing conversations are detected automatically.

Cards display **Unsubscribe** prominently.

Two unsubscribe mechanisms exist.

### **Local unsubscribe**

Future emails from the sender are hidden within the app.

### **Future agent unsubscribe**

A later version may allow AI agents to attempt to complete unsubscribe flows on external websites.

This capability is outside the MVP scope.

---

# **5.9 What the Product Does Not Include**

Decision Inbox intentionally excludes several areas to maintain focus.

---

### **Email Hosting**

The product does not replace email providers.

Users continue to use existing email accounts.

---

### **Enterprise Collaboration**

The product does not attempt to replicate enterprise communication tools such as:

* shared inboxes

* corporate ticketing systems

* internal team workflows

---

### **Automatic Email Responses**

AI does not send messages automatically.

Users must approve and send all communication.

This prevents unintended communication between automated systems.

---

### **Complex Workflow Automation**

The product is not a task manager or workflow automation platform.

Its purpose is to improve **email comprehension and control**, not replace productivity software.

---

# **5.10 Product Boundaries**

Decision Inbox focuses on improving how users:

Understand email

Prioritize conversations

Avoid scams

Control unwanted messages

Respond to communication

It does not attempt to replace:

Email infrastructure

Enterprise communication platforms

Full productivity suites

---

# **5.11 Product Success Criteria**

The product succeeds when users can:

Understand their inbox faster

Process emails without opening most messages

Remove unwanted marketing emails easily

Recognize suspicious emails confidently

Respond to conversations efficiently

The key metric is **reduced cognitive effort when managing email**.

---

# **Section 5 Summary**

Decision Inbox focuses on:

Inbox interpretation

Conversation feed

Card-based interaction

Protection systems

AI-assisted reasoning

The scope intentionally prioritizes **clarity, safety, and control** over feature complexity.

---

Next would be **Section 6: Core System Model**, which defines the internal objects that power the system (conversations, messages, senders, cards, discussions, and actions).

# **Section 6: Core System Model**

## **Section 6: Core System Model**

This section defines the **fundamental system objects and relationships** that power the product.

The goal is to establish a **clear data and interface model** that supports the product’s core principles:

* meaning before metadata

* conversations over messages

* fast understanding

Decision Inbox reorganizes email around **conversations and decisions**, not individual messages.

The system is built from the following core entities:

User

Email Account

Sender

Conversation

Message

Card

Attachment

Status

Action

Discussion

Each entity corresponds to a functional part of the user experience.

---

# **6.1 User**

The **User** represents the person using the application.

User attributes include:

User ID

Connected email accounts

Feed preference (Chronological or Relevance)

Saved conversations

Hidden senders

Blocked senders

Subscription controls

A user may connect multiple email accounts.

All connected accounts feed into a **single unified conversation feed**.

---

# **6.2 Email Account**

An **Email Account** represents a mailbox connected to the application.

Examples include accounts from:

* Gmail

* Outlook

* Yahoo Mail

Account attributes include:

Account ID

Provider

Authentication credentials

Sync status

Connected folders

The system synchronizes messages from these accounts and converts them into conversations.

---

# **6.3 Sender**

A **Sender** represents the entity that originated an email.

Senders may be:

Individuals

Organizations

Marketing lists

Unknown senders

Sender attributes include:

Email address

Display name

Domain

Sender classification

Relationship signal

Risk score

Subscription flag

Sender classification helps determine whether the sender is:

Known person

Company

Promotion

Potential scam

These signals influence conversation ranking and status labeling.

---

# **6.4 Conversation**

A **Conversation** represents a thread of related email messages.

The conversation is the **primary object displayed in the inbox feed**.

Conversation attributes include:

Conversation ID

Participants

Messages

Latest message timestamp

Intent

Quote

Status

Risk score

Subscription flag

Attachments

Each conversation appears as a **card** in the feed.

When a new message arrives in the thread:

The conversation updates

Intent may update

Quote may update

Status may change

The card moves to the top of the feed

This prevents the inbox from filling with multiple entries from the same thread.

---

# **6.5 Message**

A **Message** represents an individual email within a conversation.

Message attributes include:

Message ID

Sender

Recipients

Subject

Body content

Attachments

Timestamp

Links

Messages are only displayed when the user opens the **full conversation thread**.

The feed itself does not display individual messages.

---

# **6.6 Card**

The **Card** is the visual representation of a conversation in the inbox feed.

Each card contains three structural layers:

Header

Carousel body

Action row

---

## **Header**

The header identifies the sender and exposes key controls.

Structure:

Sender    Relationship OR Unsubscribe    •••

Examples:

Bob Chen        Friend

Delta Airlines  Company

Nike            Unsubscribe

Marketing emails replace the relationship signal with **Unsubscribe** so users can quickly remove unwanted messages.

---

## **Carousel Body**

The card body is a **carousel** that allows users to preview the email.

The structure of the carousel depends on the **type of email**.

Two presentation modes exist.

---

### **Standard Email Presentation**

Most emails are interpreted and displayed using the AI summary system.

Carousel structure:

1\. Intent card

2\. Attachment preview(s) (if present)

3\. Open full email

---

#### **Intent Card**

The first carousel page always contains the **intent summary**.

Components:

Intent

Quote

Status

Example:

Schedule intro call

"Would love to schedule a quick intro next week."

● Waiting on you

This card provides enough context for users to triage the email quickly.

---

#### **Attachment Previews**

If attachments exist, additional carousel pages appear showing previews.

Supported preview types include:

Images

PDFs

Documents

Tickets

Receipts

These previews allow users to inspect files without opening the thread.

---

#### **Open Full Email**

The final carousel page allows users to open the complete email thread.

Open full email

This provides a consistent navigation endpoint.

---

### **Marketing Email Presentation**

Marketing emails are handled differently.

Marketing emails are often **already designed visually**, typically using HTML layouts.

Instead of interpreting or summarizing these emails, the card displays:

The first visible 1:1 section of the marketing email

This behaves similarly to how ads appear in feeds on platforms like Instagram.

Users can quickly scroll past these emails if they are not interested.

Marketing cards still include:

Unsubscribe control

Primary actions

Overflow menu

This approach avoids unnecessary reinterpretation while preserving the sender’s visual design.

---

# **6.7 Attachment**

An **Attachment** represents a file included in an email.

Attachment attributes include:

Attachment ID

File type

Preview thumbnail

File size

Source message

Attachments appear as carousel items when present.

---

# **6.8 Status**

Status represents the **current state of the conversation** relative to the user.

Possible statuses include:

Waiting on you

Waiting on them

FYI

Promotion

Potential scam

Status communicates:

Whether action is required

Whether the message is informational

Whether the message may be risky

Risk signals are grouped within the status system.

---

# **6.9 Action**

Actions represent the operations users can perform on a conversation.

Primary actions appear on every card:

Reply

Discuss

Forward

Save

Archive

Additional actions appear in the overflow menu.

Reply all

Open thread

Delete

Move to label

Mark unread

Mute thread

Block sender

Report scam

Unsubscribe

Hide sender

Actions operate on the **conversation object**, not individual messages.

---

# **6.10 Discussion**

A **Discussion** represents the AI-assisted conversation attached to an email conversation.

Discussion attributes include:

Discussion ID

Associated conversation

User messages

AI responses

Context references

Discussions persist with the conversation, allowing users to return to previous reasoning and context.

---

# **6.11 Object Relationships**

The system follows this relationship structure:

User

 └─ Email Accounts

      └─ Conversations

           ├─ Messages

           ├─ Card

           ├─ Attachments

           ├─ Status

           └─ Discussion

Sender data connects to messages and conversations.

Actions operate on conversations.

---

# **6.12 Feed Generation**

The inbox feed is generated from conversation cards.

Cards are ordered according to the selected feed mode.

### **Chronological Feed**

Cards are ordered by the timestamp of the most recent message.

### **Relevance Feed**

Cards are ranked using signals such as:

Action requirement

Relationship strength

Conversation recency

Risk signals

Promotion classification

This ranking system prioritizes conversations most likely to require user attention.

---

# **Section 6 Summary**

The system is built around the following core objects:

User

Email Account

Sender

Conversation

Message

Card

Attachment

Status

Action

Discussion

The **conversation** is the central object in the system, and the **card** is its visual representation in the inbox feed.

Marketing emails are displayed using their existing visual layout, while standard emails are interpreted into intent-based cards.

This structure enables the inbox to prioritize **understanding and decision-making rather than scanning individual messages**.

# **Section 7: Core Features**

## **Section 7: Core Features**

This section describes the **primary capabilities users interact with**.

These features translate the system model into the actual product experience.

The features are designed to help users:

Understand emails faster

Remove unwanted messages

Avoid scams

Respond to conversations efficiently

The core features of Decision Inbox are:

Conversation feed

Conversation card system

Email interaction actions

Thread view

AI discussion

Scam detection

Subscription control

Sender management

---

# **7.1 Conversation Feed**

## **Description**

The inbox is presented as a **feed of conversation cards**.

Each card represents a **conversation thread**.

The feed focuses on **conversations that require attention**, rather than individual messages.

---

## **Conversation Updates**

When a new email arrives within a thread:

The conversation updates

The card moves to the top of the feed

Intent and quote may update

Status may change

This prevents inbox clutter caused by multiple messages in the same conversation.

---

## **Feed Modes**

Users can choose between two feed modes.

### **Chronological Feed**

Cards appear in order of most recent conversation activity.

### **Relevance Feed**

Cards are ranked by AI using signals such as:

Action requirement

Relationship strength

Conversation recency

Risk signals

Promotion classification

The relevance feed prioritizes conversations most likely to require attention.

---

# **7.2 Conversation Card System**

The conversation card is the **primary interface element** of the product.

Each card summarizes the meaning of an email conversation.

Cards contain three structural layers:

Header

Carousel body

Action row

---

## **Card Header**

The header identifies the sender and provides key controls.

Structure:

Sender    Relationship OR Unsubscribe    •••

Examples:

Bob Chen        Friend

Delta Airlines  Company

Nike            Unsubscribe

Marketing emails replace the relationship label with **Unsubscribe** to make it easier to remove unwanted messages.

---

## **Carousel Body**

The card body is a **carousel preview system**.

The carousel allows users to preview content without opening the thread.

Two presentation modes exist depending on email type.

---

### **Standard Email Carousel**

Standard emails use AI interpretation.

Carousel structure:

1\. Intent card

2\. Attachment preview(s) (if present)

3\. Open full email

---

#### **Intent Card**

The first carousel item contains the **AI summary**.

It includes:

Intent

Quote

Status

Example:

Schedule intro call

"Would love to schedule a quick intro next week."

● Waiting on you

This card allows users to quickly determine what the email is about.

---

#### **Attachment Previews**

If attachments exist, each attachment appears as a separate carousel page.

Examples include:

Images

PDFs

Documents

Tickets

Receipts

This allows users to inspect files quickly without opening the full thread.

---

#### **Open Full Email**

The final carousel page always contains:

Open full email

Selecting this opens the conversation thread view.

---

### **Marketing Email Carousel**

Marketing emails are displayed using their **existing HTML design**.

Instead of interpreting the message, the card displays:

The first 1:1 section of the marketing email

This preserves the original visual design.

Marketing cards behave similarly to promotional content in feeds such as Instagram.

Users can scroll past these quickly if uninterested.

The card still includes:

Unsubscribe control

Primary actions

Overflow menu

---

# **7.3 Email Interaction Actions**

Users can interact with emails directly from the card.

Primary actions appear below every card.

Reply

Discuss

Forward

Save

Archive

These actions remain **consistent across all cards**.

Consistency allows users to process emails quickly.

---

## **Reply**

Opens the email composer to respond to the sender.

---

## **Discuss**

Opens the AI discussion interface for interpreting the message or thinking through a response.

---

## **Forward**

Opens the composer to forward the email to another recipient.

---

## **Save**

Marks the conversation as saved.

Saved conversations appear in a **Saved view** for later reference.

---

## **Archive**

Removes the conversation card from the inbox feed.

Archived conversations remain searchable.

---

## **Overflow Menu**

Additional actions are available through the overflow menu.

Reply all

Open thread

Delete

Move to label

Mark unread

Mute thread

Block sender

Report scam

Unsubscribe

Hide sender

---

# **7.4 Thread View**

Thread view displays the **full email conversation**.

Users can access it by:

* opening the final carousel page

* selecting “Open thread” from the overflow menu

Thread view displays:

Full email messages

Attachments

Message history

Reply and forward controls

Messages appear in chronological order.

---

# **7.5 AI Discussion System**

Each conversation includes an **AI discussion interface**.

Users can open this by selecting **Discuss**.

The discussion interface appears as a **bottom sheet conversation view**.

This interaction pattern is similar to comment discussions in Instagram.

---

## **AI Capabilities**

Users can ask questions such as:

What does this email mean?

What is the sender asking for?

Summarize this conversation

Is this email legitimate?

What should I say in response?

The AI uses the full conversation context when responding.

---

## **AI Boundaries**

AI can:

Interpret messages

Explain context

Summarize conversations

Suggest responses

Identify potential scams

AI cannot:

Send emails automatically

Respond on behalf of the user

Communicate with other AI systems

Users always control communication.

---

# **7.6 Scam Detection**

Decision Inbox analyzes incoming messages to identify potential scams.

Signals may include:

Domain mismatch

Impersonation patterns

Suspicious links

Urgent financial requests

Unrecognized senders

Suspicious emails receive a status such as:

⚠ Potential scam

Users can take actions such as:

Report scam

Delete message

Block sender

Discuss with AI

---

# **7.7 Subscription Control**

Marketing emails are detected automatically.

Promotional conversations receive the status:

Promotion

The card header surfaces **Unsubscribe**.

This allows users to remove marketing messages quickly.

---

## **Local Unsubscribe**

Selecting unsubscribe hides future emails from that sender within the app.

Even if the sender continues sending messages, they will not appear in the feed.

---

## **Future Agent Unsubscribe**

A future version may allow AI to attempt to complete unsubscribe flows automatically on external websites.

This capability is not part of the MVP.

---

# **7.8 Sender Management**

Users can manage senders through several controls.

Hide sender

Block sender

Mute thread

Report scam

These tools help users maintain a clean inbox.

---

# **Section 7 Summary**

Decision Inbox includes the following core features:

Conversation feed

Conversation card system

Card carousel previews

Email interaction actions

Thread view

AI discussion assistant

Scam detection

Subscription control

Sender management

Together these features transform the inbox into a system focused on:

Clarity

Safety

Control

# **Section 8: Interaction Flows**

## **Section 8: Interaction Flows**

This section describes **how users interact with the product in real situations**.

The product is designed around one core behavior:

Quickly understand → decide → move on

Most emails should be handled **directly from the feed** without opening the full thread.

The major interaction flows include:

Onboarding

Processing the inbox

Replying to emails

Discussing an email with AI

Handling proactive AI comments

Unsubscribing from marketing emails

Handling suspicious emails

Opening the full email thread

Saving and archiving conversations

---

# **8.1 Onboarding**

### **Goal**

Connect the user’s email account and generate their first interpreted inbox.

---

### **Flow**

**Step 1 — Welcome**

User opens the app and sees a short explanation.

Example:

Understand your inbox faster

Avoid scams

Control unwanted email

---

**Step 2 — Connect Email**

User connects their email provider.

Supported providers include:

* Gmail

* Outlook

* Yahoo

Authentication occurs via secure OAuth.

---

**Step 3 — Inbox Analysis**

The system analyzes the inbox.

During this process the system:

Groups messages into conversations

Identifies senders

Detects marketing emails

Scans for scams

Extracts intent

Selects supporting quotes

Generates conversation cards

---

**Step 4 — First Feed**

User lands on the **conversation feed**.

A short overlay explains the card.

Example explanation:

Intent → what the email is about

Quote → real text from the email

Status → whether action is required

Carousel → preview attachments or open the full email

Actions → reply, discuss, archive

User begins processing their inbox.

---

# **8.2 Processing the Inbox**

### **Goal**

Allow users to quickly understand and handle most emails without opening them.

---

### **Flow**

User scrolls through the feed.

Each card shows:

Sender

Intent

Quote

Status

Carousel preview

Actions

Users typically take one of four actions:

Scroll past

Archive

Reply

Discuss

Most emails are resolved directly from the card.

---

### **Example Triage Session**

User scrolls through several cards:

Nike sale email → scroll past

Delivery update → scroll past

Recruiter email → reply

Customer survey → unsubscribe

Suspicious banking email → delete

The inbox is processed quickly.

---

# **8.3 Replying to an Email**

### **Goal**

Allow users to respond quickly when action is required.

---

### **Flow**

**Step 1 — Tap Reply**

User taps **Reply** on the card.

---

**Step 2 — Composer Opens**

Composer includes:

To

Subject

Reply text field

Attachment controls

Send button

The original message appears below for reference.

---

**Step 3 — Send**

User sends the reply.

Conversation status may update to:

Waiting on them

User returns to the feed.

---

# **8.4 Discussing an Email With AI**

### **Goal**

Allow users to interpret emails or think through responses.

---

### **Flow**

**Step 1 — Tap Discuss**

User selects **Discuss** on the card.

---

**Step 2 — Discussion Bottom Sheet**

A discussion interface slides up.

The interface contains:

Conversation context

User input field

AI responses

---

**Step 3 — Ask Question**

User asks something like:

What does this email mean?

What is the sender asking for?

Is this legitimate?

What should I say?

---

**Step 4 — AI Response**

AI analyzes the thread and provides an explanation.

Example:

The sender is asking you to confirm availability for a meeting next week.

They suggested Tuesday or Wednesday.

You may want to confirm which time works for you.

The user can continue the discussion or close it.

---

# **8.5 Proactive AI Comments**

### **Goal**

Surface helpful context before the user asks for it.

In certain situations the AI automatically posts a **discussion comment**.

These comments appear when the user opens the discussion view.

---

### **Scenario 1 — Scam Detection**

If the email is flagged as suspicious, the discussion already contains a warning.

Example:

This email may be a phishing attempt.

The sender claims to be PayPal, but the email domain is:

paypal-account-security.net

Legitimate PayPal emails typically come from:

@paypal.com

The message also asks for urgent account verification.

---

### **Scenario 2 — Recurring Conversation**

If a thread has multiple messages, the AI summarizes the current state.

Example:

This thread has 5 messages.

Current state:

They asked you to confirm availability for a call.

You have not responded yet.

---

### **Scenario 3 — Long Email Summary**

If an email is unusually long, the AI provides a short summary.

Example:

Summary:

Your flight departure time changed from 2:10 PM to 3:05 PM.

No action required unless you want to change flights.

---

### **Scenario 4 — Attachment Explanation**

If attachments are present, the AI may explain what they contain.

Example:

This email contains a PDF contract.

The sender is asking you to review and confirm the terms.

---

### **Scenario 5 — Survey or Marketing Context**

If the email is a survey request or automated outreach.

Example:

This email is requesting feedback about your recent purchase.

These emails are automated and optional.

You can safely ignore it if you prefer.

---

# **8.6 Unsubscribing From Marketing Emails**

### **Goal**

Allow users to remove unwanted promotional messages quickly.

---

### **Flow**

**Step 1 — Marketing Email Appears**

The card header displays:

Unsubscribe

---

**Step 2 — Tap Unsubscribe**

User selects unsubscribe.

---

**Step 3 — Local Filtering**

Future emails from the sender are hidden from the feed.

---

**Step 4 — Confirmation**

User receives confirmation that the sender has been unsubscribed.

---

# **8.7 Handling Suspicious Emails**

### **Goal**

Help users recognize and safely handle scams.

---

### **Flow**

**Step 1 — Suspicious Email Appears**

Card status shows:

⚠ Potential scam

---

**Step 2 — User Options**

User may:

Delete

Block sender

Report scam

Discuss with AI

---

**Step 3 — AI Explanation**

If the user opens discussion, the AI explains the risk signals.

Example:

The sender domain does not match the organization name.

The message requests urgent account verification.

The link appears unrelated to the sender.

---

# **8.8 Opening the Full Email**

### **Goal**

Allow users to read the complete message when needed.

---

### **Flow**

**Step 1 — Scroll Carousel**

User scrolls the card carousel.

---

**Step 2 — Select Final Page**

The final carousel page shows:

Open full email

---

**Step 3 — Thread View Opens**

Thread view displays:

Full messages

Attachments

Message history

Reply controls

---

# **8.9 Saving a Conversation**

### **Goal**

Preserve important conversations.

---

### **Flow**

**Step 1 — Tap Save**

User selects **Save**.

---

**Step 2 — Conversation Stored**

Conversation appears in a **Saved view** for later access.

---

# **8.10 Archiving a Conversation**

### **Goal**

Remove completed conversations from the inbox feed.

---

### **Flow**

**Step 1 — Tap Archive**

User selects **Archive**.

---

**Step 2 — Card Removed**

Conversation disappears from the feed.

---

**Step 3 — Conversation Remains Searchable**

Archived conversations remain accessible through search.

---

# **Section 8 Summary**

Key interaction flows include:

Onboarding

Inbox processing

Replying to emails

AI discussion

Proactive AI explanations

Unsubscribing from marketing emails

Handling suspicious emails

Opening full threads

Saving conversations

Archiving conversations

These flows enable users to process their inbox **quickly, safely, and with minimal reading**.

---

Next would be **Section 9: AI System Design**, which defines:

* how intent is generated

* how quotes are selected

* how scams are detected

* how conversations are ranked in the relevance feed.

# **Section 9: AI System Design**

## **Section 9: AI System Design**

This section defines **how AI operates inside Decision Inbox**.

AI is central to the product. It powers:

Intent generation

Quote selection

Status assignment

Scam detection

Marketing detection

Relevance ranking

Discussion assistance

Proactive discussion comments

The AI system exists to help users **understand email quickly and safely**.

It does **not** exist to communicate on the user’s behalf.

---

# **9.1 AI Role in the Product**

AI has two jobs:

Interpret the inbox

Support user reasoning

Interpret the inbox means transforming raw email into usable card-level signals:

Intent

Quote

Status

Risk

Promotion classification

Support user reasoning means helping users understand emails in the discussion interface.

AI does **not** send messages automatically.

---

# **9.2 AI Principles**

The AI system must follow these rules.

### **1\. Be useful before being impressive**

The AI should prioritize:

clarity

accuracy

brevity

over cleverness.

---

### **2\. Prefer structured judgment over open-ended generation**

The AI should not behave like a general chatbot by default.

Its primary purpose is to extract:

intent

quote

status

risk

from email conversations.

---

### **3\. Show evidence**

Whenever AI interprets meaning, users must be able to verify it through:

quote

sender identity

status

full thread access

---

### **4\. Be selectively proactive**

AI should only proactively comment when it materially reduces:

risk

confusion

reading effort

It should not comment on every email.

---

### **5\. Never communicate for the user**

AI can help users think, summarize, and draft.

AI cannot:

send

reply automatically

negotiate on behalf of the user

---

# **9.3 AI Outputs Per Conversation**

For each conversation, the AI system produces a structured set of outputs.

Intent

Quote

Status

Risk score

Promotion classification

Proactive discussion comment (optional)

Relevance features

These outputs power the card and feed experience.

---

# **9.4 Intent Generation**

## **Purpose**

Intent is the **primary interpretation layer** of the card.

It answers:

What is this email about?

in a way that is useful for decision-making.

---

## **Format**

Intent must be:

Action-oriented

Short

Readable

Specific

Structure:

Verb \+ object

Examples:

Schedule intro call

Confirm dinner plans

Review attached contract

Verify account information

Complete feedback survey

Track package delivery

Not:

Intro call

Dinner

Contract

Account

Survey

---

## **Intent Rules**

The model should follow these rules.

### **Rule 1**

Prioritize **what the user is being asked to understand or do**.

### **Rule 2**

Use 2–5 words where possible.

### **Rule 3**

Avoid filler words.

Bad:

They want to schedule a call

Good:

Schedule call

### **Rule 4**

If there are multiple requests, choose the **single most important intent**.

### **Rule 5**

For purely informational messages, use an action-oriented interpretation where possible.

Examples:

Track package delivery

Review billing update

View flight delay

---

## **Intent Input Scope**

Intent is generated from:

latest message

prior thread context

participants

attachments

sender type

The model should not rely only on the subject line.

---

# **9.5 Quote Selection**

## **Purpose**

The quote is the **trust anchor** for the AI interpretation.

It answers:

Why does the AI think this is the intent?

---

## **Requirements**

The quote must be:

Real text from the email

Short

Representative

Easy to scan

The quote should support the intent directly.

Example:

Intent:

Schedule intro call

Quote:

"Would love to schedule a quick intro next week."

---

## **Quote Selection Rules**

### **Rule 1**

Select the sentence or phrase that best supports the chosen intent.

### **Rule 2**

Prefer plain-language excerpts over greetings or signatures.

Do not select:

Hi Craig,

Best,

Thanks,

### **Rule 3**

Prefer the latest relevant message in the thread.

### **Rule 4**

If no single sentence is ideal, choose the shortest excerpt that best signals meaning.

### **Rule 5**

Do not paraphrase in the quote field. It must be verbatim from the email.

---

# **9.6 Status Assignment**

## **Purpose**

Status communicates:

What should I do about this?

It is the conversation’s state relative to the user.

---

## **Core Status Values**

Waiting on you

Waiting on them

FYI

Promotion

Potential scam

---

## **Status Rules**

### **Waiting on you**

Use when the conversation likely requires user action.

Examples:

* direct question

* scheduling request

* review request

* confirmation request

---

### **Waiting on them**

Use when the user has already replied or acted and the next step is on the other party.

---

### **FYI**

Use for informational updates where action is not clearly required.

Examples:

* receipts

* confirmations

* delivery updates

* travel alerts

---

### **Promotion**

Use when the message is marketing-oriented or subscription-like.

Examples:

* newsletters

* sales

* feedback surveys

* brand outreach

---

### **Potential scam**

Use when the message crosses a risk threshold based on scam detection signals.

---

# **9.7 Scam Detection System**

## **Purpose**

Help users identify suspicious emails before they click, respond, or trust them.

---

## **Inputs**

Scam analysis may use:

sender identity

domain mismatch

message wording

urgency patterns

link destinations

brand impersonation cues

recipient context

thread history

---

## **Common Scam Signals**

Examples include:

Urgent account verification

Threat of account lockout

Unexpected financial request

Brand mismatch with sender domain

Suspicious login or package alerts

Requests to click unfamiliar links

---

## **Output**

The scam system produces:

Risk score

Potential scam status (if threshold exceeded)

Reasoning summary for discussion layer

The card itself only shows:

⚠ Potential scam

The detailed explanation appears in the discussion layer.

---

## **Example Proactive Scam Comment**

This email may be a phishing attempt.

Reasons:

• The sender claims to be Bank of America, but the domain does not match.

• The message asks for urgent verification.

• The link destination appears unrelated to the sender.

Recommendation:

Do not click the link. Access your account directly through the official website or app.

---

# **9.8 Promotion and Subscription Detection**

## **Purpose**

Identify email that is primarily:

marketing

newsletter

survey

promotional outreach

This enables:

* promotion status

* unsubscribe surfacing

* lower ranking in relevance feed

* local unsubscribe behavior

---

## **Signals**

Promotion detection may use:

bulk-sent structure

newsletter formatting

marketing language

unsubscribe links

brand campaign patterns

survey request wording

---

## **Output**

The system produces:

Promotion classification

Subscription flag

If positive:

* status becomes Promotion

* header shows Unsubscribe

* marketing email presentation rules apply

---

# **9.9 Marketing Email Presentation Logic**

Marketing emails use a different card-body presentation than standard emails.

---

## **Standard Emails**

Use AI interpretation.

Carousel structure:

1\. Intent card

2\. Attachment preview(s), if present

3\. Open full email

---

## **Marketing Emails**

Do **not** render an AI intent card as the primary surface.

Instead, show:

The first visible 1:1 section of the email’s existing HTML design

This preserves the fact that marketing emails are already visually designed.

The user can treat them like ad-like feed objects and scroll past quickly.

These cards still include:

Header

Status

Primary actions

Overflow menu

And the header prominently surfaces:

Unsubscribe

---

## **Why Marketing Uses Different Presentation**

The product assumption is:

Marketing emails are already optimized visually.

Users recognize them quickly.

Trying to reinterpret them with AI may be less useful than preserving their existing signal.

AI still classifies them as promotion, but the body presentation remains visual.

---

# **9.10 Proactive AI Comments**

## **Purpose**

Some emails benefit from AI commentary before the user asks for help.

Proactive AI comments appear in the **discussion bottom sheet** when the user opens Discuss.

They do not clutter the main feed.

---

## **Trigger Conditions**

A proactive comment may be generated when one of the following is true.

### **1\. Scam risk**

The email is flagged as suspicious.

### **2\. Recurring conversation**

The thread has enough back-and-forth that users may need a refresher.

### **3\. Long or dense message**

The email is unusually long or instruction-heavy.

### **4\. Attachment significance**

The key meaning of the email is inside an attachment.

### **5\. Survey or low-value request**

The user is likely deciding whether they can safely ignore the message.

---

## **Example Proactive Comments**

### **Scam**

This email may be a phishing attempt.

The sender domain does not match the company name, and the message asks for urgent account verification.

### **Recurring thread**

This thread has 6 messages.

Current state:

They asked you to confirm availability for Tuesday or Wednesday.

You have not responded yet.

### **Long email**

Summary:

Your flight changed from 2:10 PM to 3:05 PM.

No action is required unless you want to change your itinerary.

### **Attachment-driven email**

This email includes a contract PDF.

The sender is asking you to review and confirm the terms before Friday.

### **Survey / optional request**

This email is asking for customer feedback.

This request is optional and can be ignored if you do not want to participate.

---

# **9.11 Discussion Assistant**

## **Purpose**

The discussion layer lets users reason about an email with AI.

It is not just a chatbot. It is a **context-aware interpretation assistant**.

---

## **User Questions It Should Handle Well**

What does this email mean?

What are they asking for?

Is this legitimate?

Summarize this thread

What should I say?

What’s the key deadline here?

What changed since the last message?

---

## **Discussion Input Context**

The discussion assistant may use:

full thread history

latest message

intent

quote

status

sender info

attachments

prior discussion in the same conversation

This allows the AI to preserve continuity.

---

## **Tone of Discussion Assistant**

The assistant should be:

clear

calm

direct

practical

It should avoid sounding overly robotic or overly verbose.

---

# **9.12 Relevance Ranking System**

## **Purpose**

Power the optional **Relevance feed** by ordering conversations based on likely importance.

The system changes order, not visibility.

---

## **Inputs to Ranking**

Possible ranking signals include:

Status (especially Waiting on you)

Relationship strength

Conversation recency

Directness of request

Potential opportunity signals

Promotion classification

Risk signals

User behavior history

Saved status

Unread / unresolved state

---

## **Ranking Philosophy**

The relevance system should prioritize:

Conversations likely requiring action

Messages from important senders

Time-sensitive updates

Potential opportunities

and deprioritize:

Promotions

Low-value surveys

Repeated bulk mail

Resolved or passive threads

---

## **Trust Rule**

Users must always be able to switch back to:

Chronological

The relevance feed should never feel like things have disappeared.

---

# **9.13 AI Failure Modes and Safeguards**

Because the AI system is central, failures must be anticipated.

---

## **Failure Mode 1: Wrong intent**

Example:

AI says:

FYI update

but the email actually needs action.

### **Safeguard**

* show quote for verification

* allow easy open-thread fallback

* make intent concise and humble, not overconfident

---

## **Failure Mode 2: False scam label**

Example:

A legitimate email is flagged as suspicious.

### **Safeguard**

* detailed reasoning only in discussion layer

* users can override and continue

* risk shown as caution, not hard block

---

## **Failure Mode 3: Missed scam**

Example:

A phishing email is treated as normal.

### **Safeguard**

* rely on layered signals

* allow easy report scam action

* discussion can still help interpret manually

---

## **Failure Mode 4: Noisy proactive comments**

Example:

AI comments on too many emails.

### **Safeguard**

* strict trigger thresholds

* proactive comments only for high-value or high-risk cases

* keep proactive comments inside discussion layer

---

## **Failure Mode 5: Unhelpful quote**

Example:

The quote does not support the intent.

### **Safeguard**

* quote selection tuned specifically for supporting-evidence quality

* always use latest relevant excerpt when possible

---

# **9.14 AI Performance Requirements**

For the product to work, AI outputs must feel:

fast

consistent

trustworthy

User tolerance will be low because AI sits at the center of the inbox experience.

Minimum product expectations:

Intent feels right most of the time

Quote clearly supports intent

Promotion detection is obvious and reliable

Scam explanations are understandable

Discussion context persists correctly

---

# **9.15 Section 9 Summary**

The AI system powers the core value of Decision Inbox through:

Intent generation

Quote selection

Status assignment

Scam detection

Promotion detection

Marketing-specific presentation logic

Proactive discussion comments

Discussion assistance

Relevance ranking

AI is used to help users:

Understand

Prioritize

Stay safe

Think through responses

while preserving the key product rule:

AI helps users think.

Users communicate.

---

Next would be **Section 10: Action System and Controls**, where we define every action available on the card, in the overflow menu, in thread view, and in discussion, along with their behaviors and edge cases.

# **Section 10: Action System and Controls**

## **Section 10: Action System and Controls**

This section defines **all user actions available in the product** and where they appear.

The action system is designed around three principles:

Predictability

Speed

Control

Actions should allow users to resolve most emails **directly from the conversation card**.

The product intentionally uses a **consistent action set across all cards** so users develop muscle memory.

---

# **10.1 Action System Overview**

There are three levels of actions in the product.

Primary card actions

Overflow actions

Thread-level actions

Each level serves a different purpose.

---

## **Primary Card Actions**

These are the **most common actions** users take when processing email.

They appear on every card.

Reply

Discuss

Forward

Save

Archive

---

## **Overflow Actions**

Less common actions are accessed through the overflow menu (•••) in the card header.

Reply all

Open thread

Delete

Move to label

Mark unread

Mute thread

Block sender

Report scam

Unsubscribe

Hide sender

---

## **Thread-Level Actions**

These actions appear when the user opens the **full thread view**.

Reply

Reply all

Forward

Archive

Delete

Discuss

Thread view actions focus on message-level interaction.

---

# **10.2 Primary Card Actions**

Primary actions appear below the card carousel.

Structure:

Reply   Discuss   Forward   Save   Archive

These actions remain **identical on all cards**.

This consistency allows users to process their inbox quickly.

---

## **Reply**

### **Purpose**

Respond to the sender.

### **Behavior**

Selecting **Reply** opens the email composer.

Composer fields include:

To

Subject

Reply body

Attachment controls

Send button

The original message appears below the composer for context.

---

### **Result**

Once the reply is sent:

Conversation status may update

Status may become "Waiting on them"

Card may move based on feed rules

---

## **Discuss**

### **Purpose**

Open the AI discussion assistant.

### **Behavior**

Selecting **Discuss** opens a bottom-sheet conversation interface.

The discussion allows users to:

Interpret the email

Ask questions

Summarize the thread

Think through responses

Verify legitimacy

The discussion persists with the conversation.

---

### **Special Case**

If the AI has generated a **proactive comment**, it appears at the top of the discussion.

Examples:

Scam explanation

Thread summary

Attachment explanation

Long-email summary

---

## **Forward**

### **Purpose**

Send the email to another recipient.

### **Behavior**

Selecting **Forward** opens the composer with the email content included.

Composer fields include:

To

Subject

Forward body

Attachment controls

Send button

---

## **Save**

### **Purpose**

Preserve important conversations.

### **Behavior**

Selecting **Save** marks the conversation as saved.

Saved conversations appear in a **Saved view**.

Saved conversations may also receive slight ranking preference in the relevance feed.

---

## **Archive**

### **Purpose**

Remove completed conversations from the inbox feed.

### **Behavior**

Selecting **Archive** removes the card from the feed.

The conversation remains accessible through:

Search

Thread view

Saved view (if saved)

Archiving does not delete the email.

---

# **10.3 Overflow Menu Actions**

The overflow menu contains less frequently used controls.

It appears as:

•••

in the card header.

---

## **Reply All**

Respond to all participants in the thread.

Composer includes all recipients.

---

## **Open Thread**

Open the full thread view directly.

This is equivalent to the **final carousel page action**.

---

## **Delete**

Remove the conversation permanently.

Behavior:

Conversation removed from inbox

Messages moved to provider trash

---

## **Move to Label**

Allows users to apply labels or folders.

Example labels may include:

Work

Finance

Travel

Personal

Labels mirror the connected email provider’s label system.

---

## **Mark Unread**

Allows users to mark the conversation as unread.

This helps users return to a conversation later.

---

## **Mute Thread**

Prevents future messages in the thread from resurfacing in the feed.

Muted threads remain searchable.

---

## **Block Sender**

Blocks the sender.

Future emails from that sender will not appear in the inbox feed.

---

## **Report Scam**

Allows users to flag suspicious emails.

Reported scams may improve the scam detection system.

---

## **Unsubscribe**

Appears primarily for marketing conversations.

Selecting unsubscribe:

Hides future emails from the sender

The system performs a **local unsubscribe** inside the app.

Future emails from the sender will not appear in the feed.

---

## **Hide Sender**

Allows users to hide all emails from a sender without fully blocking them.

Hidden senders remain accessible via search if needed.

---

# **10.4 Thread-Level Actions**

When the user opens the full thread view, additional controls appear.

Thread view actions include:

Reply

Reply all

Forward

Archive

Delete

Discuss

Thread view also allows:

Reading full messages

Viewing attachments

Scrolling through message history

Thread-level actions behave similarly to card actions but operate within the full message context.

---

# **10.5 Action Design Principles**

The action system follows several design rules.

---

## **Rule 1: Consistency**

Primary actions never change location or meaning.

Every card includes the same actions.

---

## **Rule 2: Resolve From the Feed**

Most emails should be resolvable **without opening the thread**.

Examples:

Reply directly

Archive quickly

Unsubscribe instantly

Delete scams

---

## **Rule 3: Avoid Action Overload**

Only the most common actions appear on the card.

All others live in the overflow menu.

---

## **Rule 4: Preserve User Control**

Users can always override automation.

Examples:

Delete instead of archive

Open full thread

Block sender

Report scam

Automation assists but never removes control.

---

# **10.6 Edge Case Handling**

The action system must account for edge cases.

---

## **Multiple Recipients**

If multiple recipients exist:

* **Reply** responds only to the sender

* **Reply all** appears in the overflow menu

---

## **Marketing Emails**

Marketing emails still allow actions such as:

Save

Archive

Forward

Discuss

However, the header prominently surfaces **Unsubscribe**.

---

## **Scam Emails**

If an email is flagged as suspicious:

Status shows "Potential scam"

Recommended actions include:

Delete

Block sender

Report scam

Discuss

---

# **Section 10 Summary**

The action system includes:

Primary actions

Overflow actions

Thread-level actions

Primary actions:

Reply

Discuss

Forward

Save

Archive

These actions allow users to resolve most conversations directly from the feed.

The system prioritizes:

Predictability

Speed

Control

while ensuring users retain full authority over their email interactions.

---

The next section would be **Section 11: Feed Ranking and Prioritization**, which defines how the chronological and relevance feeds are generated and ordered.

# **Section 11: Feed Ranking and Prioritization**

## **Section 11: Feed Ranking and Prioritization**

This section defines **how conversations appear in the inbox feed**.

The feed is the central interface of the product. Ranking determines:

What the user sees first

What can be safely ignored

What requires attention

The goal is to reduce the user’s core problem:

Too many emails competing for attention

The product supports **two feed modes**.

Chronological feed

Relevance feed

Users can switch between them at any time.

---

# **11.1 Feed Unit**

The feed displays **conversation cards**.

A card represents:

One email thread

One subject

One conversation

When a new email arrives in a thread:

The card updates

The card may move in the feed

Intent, quote, and status may update

The feed never shows **individual messages** as separate items.

It always shows **conversations**.

---

# **11.2 Chronological Feed**

### **Purpose**

Provide a predictable, traditional inbox order.

### **Behavior**

Cards are ordered by:

Most recent message timestamp

Whenever a new message arrives:

The conversation moves to the top

---

### **Example**

10:45 — Recruiter message

10:32 — Package delivery update

10:10 — Nike sale email

09:50 — Calendar confirmation

Chronological mode mirrors how traditional inboxes work.

This mode provides **full user trust and transparency**.

---

# **11.3 Relevance Feed**

### **Purpose**

Prioritize emails most likely to matter to the user.

Instead of ordering by time, conversations are ordered by **importance signals**.

---

### **Relevance Ranking Inputs**

The ranking system evaluates multiple signals.

These may include:

Status

Relationship strength

Conversation recency

User interaction history

Promotion classification

Risk indicators

Saved status

Conversation depth

Direct request signals

Each signal contributes to a relevance score.

---

### **Example Ranking**

1\. Recruiter asking for interview availability

2\. Friend confirming dinner plans

3\. Airline schedule change

4\. Package delivery update

5\. Brand newsletter

6\. Customer survey

Even if the newsletter arrived more recently, the recruiter email appears higher.

---

# **11.4 Status Weighting**

Status is the **strongest signal** in relevance ranking.

Priority order:

Waiting on you

Potential scam

Waiting on them

FYI

Promotion

---

### **Explanation**

**Waiting on you**

These conversations likely require immediate attention.

Examples:

Interview scheduling

Direct questions

Requests for confirmation

---

**Potential scam**

Suspicious emails are surfaced to allow quick inspection or deletion.

---

**Waiting on them**

Lower urgency but still important to track.

---

**FYI**

Informational updates.

Examples:

Receipts

Shipping confirmations

Travel alerts

---

**Promotion**

Marketing emails receive the lowest ranking.

These typically appear near the bottom of the relevance feed.

---

# **11.5 Relationship Signals**

The ranking system also considers **how important the sender is to the user**.

Possible signals include:

Past reply frequency

Conversation history

Direct replies

User saving behavior

Contact presence

Senders with strong relationships rank higher.

Example:

Friend message → higher ranking

Unknown brand email → lower ranking

---

# **11.6 Conversation Activity**

Threads with recent interaction receive ranking boosts.

Signals include:

Recent replies

Active conversation

Thread depth

This ensures ongoing conversations remain visible.

Example:

Back-and-forth scheduling thread

Project coordination conversation

---

# **11.7 Promotion Demotion**

Marketing emails are intentionally ranked lower.

Signals include:

Newsletter structure

Bulk sending patterns

Unsubscribe links

Marketing language

These emails may still appear in the feed but are deprioritized.

The system assumes:

Promotions rarely require immediate action

---

# **11.8 Risk Signals**

Suspicious emails receive special handling.

If an email is classified as **Potential scam**, it may appear higher than normal promotion emails.

This allows users to:

Delete quickly

Investigate

Report scams

However, the system avoids making scam emails overly prominent.

---

# **11.9 Saved Conversation Boost**

Saved conversations receive ranking priority.

Signals include:

User marked conversation as important

User may revisit later

Saved conversations may appear higher in the relevance feed.

---

# **11.10 Feed Refresh Rules**

The feed updates dynamically as new messages arrive.

When a new email is received:

Conversation card updates

Intent may update

Quote may update

Status may update

Ranking recalculates

The conversation then moves to its appropriate position.

---

# **11.11 Relevance Transparency**

Users must be able to understand and trust the ranking system.

Two rules ensure this.

---

## **Rule 1: Chronological fallback**

Users can always switch to chronological mode.

This ensures nothing feels hidden.

---

## **Rule 2: No silent filtering**

The relevance feed **reorders conversations**.

It does not hide them.

All conversations remain:

Searchable

Accessible

Visible somewhere in the feed

---

# **11.12 Feed Completion State**

Unlike social media feeds, the inbox feed is **finite**.

When the user reaches the end:

No more conversations appear

The system may show a completion indicator.

Example:

You're caught up

This reinforces the product goal:

Help users return to their lives

rather than creating infinite engagement loops.

---

# **11.13 Future Enhancements**

Future versions of the feed may introduce:

Grouped relevance sections

Relationship hubs

Opportunity signals

Smart reminders

However, the MVP feed remains intentionally simple.

---

# **Section 11 Summary**

The feed system supports two modes:

Chronological

Relevance

Relevance ranking prioritizes signals such as:

Status

Relationships

Conversation activity

Promotion classification

Risk signals

User behavior

The system’s goal is to surface emails that most likely require attention while keeping the inbox transparent and controllable.

---

The next section would be **Section 12: Data Model**, which defines the core objects behind the product (Conversations, Messages, Senders, Cards, Discussions, and Actions).

# **Section 12: Data Model**

## **Section 12: Data Model**

This section defines the **core objects and relationships** that power Decision Inbox.

The data model exists to support three main goals:

Represent email conversations

Power the feed interface

Support AI interpretation and discussion

The system builds structured objects on top of raw email data.

Core objects include:

Account

Sender

Conversation

Message

Card

Discussion

Action

These objects form the foundation for both the product interface and AI systems.

---

# **12.1 Account**

### **Purpose**

Represents a user’s connected email identity.

An account connects the product to an external email provider.

Examples include accounts from:

* Gmail

* Outlook

* Yahoo

---

### **Key Fields**

account\_id

email\_address

provider

connection\_status

last\_sync\_time

user\_preferences

---

### **Relationships**

An account may contain:

many senders

many conversations

many messages

many saved conversations

---

# **12.2 Sender**

### **Purpose**

Represents the identity of the email sender.

This object enables relationship detection and scam analysis.

---

### **Key Fields**

sender\_id

email\_address

display\_name

domain

organization\_name

relationship\_strength

is\_contact

is\_blocked

is\_hidden

---

### **Derived Signals**

AI may generate additional signals.

sender\_type

promotion\_likelihood

risk\_profile

Sender types may include:

Person

Brand

Service

Unknown

---

### **Relationships**

A sender may appear in:

many conversations

many messages

---

# **12.3 Conversation**

### **Purpose**

Represents a thread of related emails.

A conversation is the **primary unit of the feed**.

Each card corresponds to one conversation.

---

### **Key Fields**

conversation\_id

subject

participants

first\_message\_timestamp

latest\_message\_timestamp

message\_count

conversation\_status

is\_saved

is\_archived

is\_muted

---

### **AI Interpretation Fields**

AI generates additional structured signals for each conversation.

intent

quote

status

risk\_level

promotion\_flag

These fields power the conversation card.

---

### **Relationships**

A conversation contains:

many messages

one card

one discussion thread

many actions

---

# **12.4 Message**

### **Purpose**

Represents an individual email within a conversation.

Messages contain the raw content used for AI analysis.

---

### **Key Fields**

message\_id

conversation\_id

sender\_id

recipients

timestamp

subject

body\_text

body\_html

attachments

links

---

### **Derived Fields**

AI analysis may extract:

message\_intent

message\_summary

risk\_signals

promotion\_signals

---

### **Relationships**

A message belongs to:

one conversation

one sender

---

# **12.5 Card**

### **Purpose**

Represents the **feed object shown to the user**.

The card is a presentation layer built from conversation and AI signals.

---

### **Key Fields**

card\_id

conversation\_id

sender\_display

relationship\_signal

intent

quote

status

promotion\_flag

risk\_indicator

---

### **Carousel Data**

The card also stores carousel elements.

carousel\_items

Possible carousel items include:

intent\_card

attachment\_preview

open\_full\_email

---

### **Marketing Email Presentation**

If a conversation is classified as promotion:

promotion\_flag \= true

The card body displays:

first 1:1 section of the HTML email

instead of an AI intent card.

The header still includes:

sender

status

unsubscribe

overflow menu

---

### **Relationships**

A card belongs to:

one conversation

---

# **12.6 Discussion**

### **Purpose**

Represents the AI discussion thread associated with a conversation.

This allows users to reason about an email with AI.

Each conversation has **one persistent discussion thread**.

---

### **Key Fields**

discussion\_id

conversation\_id

messages

created\_timestamp

last\_updated

---

### **Discussion Messages**

Each discussion message includes:

discussion\_message\_id

role (user or AI)

content

timestamp

---

### **Proactive AI Messages**

Some discussion threads begin with an AI-generated message.

Examples include:

scam explanation

thread summary

attachment explanation

long email summary

survey context

These messages appear when the user opens discussion.

---

# **12.7 Action**

### **Purpose**

Represents actions taken by the user on a conversation.

Actions allow the system to track interaction history.

---

### **Key Fields**

action\_id

conversation\_id

action\_type

timestamp

actor

---

### **Action Types**

Examples include:

reply

forward

save

archive

delete

unsubscribe

block\_sender

report\_scam

mark\_unread

mute\_thread

---

### **Use of Action Data**

Action history may influence:

relevance ranking

relationship signals

conversation status

user preferences

---

# **12.8 Attachment**

### **Purpose**

Represents files attached to messages.

Attachments may be surfaced in the card carousel.

---

### **Key Fields**

attachment\_id

message\_id

file\_name

file\_type

file\_size

preview\_available

---

### **Relationships**

Attachments belong to:

one message

Attachments may appear in:

card carousel previews

thread view

---

# **12.9 Feed Entry**

### **Purpose**

Represents the ordering and visibility of cards in the feed.

---

### **Key Fields**

feed\_entry\_id

card\_id

ranking\_score

feed\_mode

position

last\_updated

---

### **Feed Modes**

Possible feed modes include:

chronological

relevance

Ranking scores are recalculated when:

new message arrives

conversation status changes

user actions occur

---

# **12.10 System Relationships Overview**

The system structure can be summarized as:

Account

  ├─ Sender

  ├─ Conversation

       ├─ Message

       │     └─ Attachment

       ├─ Card

       ├─ Discussion

       │     └─ Discussion Messages

       └─ Actions

The **conversation object sits at the center** of the system.

Most product functionality operates at the conversation level.

---

# **12.11 Design Principles of the Data Model**

The model follows several structural principles.

---

### **Conversation-first architecture**

The feed operates on conversations rather than individual emails.

This simplifies the interface and ranking system.

---

### **AI as metadata**

AI outputs are stored as structured metadata.

Examples include:

intent

quote

status

promotion\_flag

risk\_indicator

This allows the interface to update quickly without recomputing AI output constantly.

---

### **Separation of interpretation and content**

Raw email content remains unchanged.

AI interpretation is stored separately.

This preserves transparency and trust.

---

# **Section 12 Summary**

The core data model includes:

Account

Sender

Conversation

Message

Card

Discussion

Action

Attachment

Feed Entry

These objects support the key product systems:

Feed interface

AI interpretation

Discussion assistant

Action system

Ranking system

The model centers around **conversation-level understanding**, enabling the product to transform email from a message list into a decision-focused feed.

---

The next section would be **Section 13: System Architecture**, which defines how the email ingestion pipeline, AI processing, feed generation, and discussion systems operate together.

# **Section 13: System Architecture**

## **Section 13: System Architecture**

This section defines **how the system works end-to-end**.

It explains how an email moves from the external provider into the product and becomes a **conversation card in the feed**.

The architecture is designed around five core pipelines:

Email ingestion

Conversation construction

AI interpretation

Feed generation

Discussion system

These pipelines operate continuously as new emails arrive.

---

# **13.1 System Overview**

At a high level, the system processes email in stages.

Email Provider

     ↓

Email Ingestion Service

     ↓

Conversation Builder

     ↓

AI Interpretation Engine

     ↓

Card Generator

     ↓

Feed Ranking System

     ↓

User Interface

Each stage transforms raw email into structured data used by the product.

---

# **13.2 Email Ingestion Pipeline**

### **Purpose**

Import emails from the user’s connected provider.

Supported providers may include:

* Gmail

* Outlook

* Yahoo

---

### **Ingestion Method**

The system connects through provider APIs using OAuth.

Typical ingestion approaches include:

Provider webhooks for new messages

Periodic sync for missed events

Initial historical import during onboarding

---

### **Data Collected**

Each email message includes:

sender

recipients

subject

timestamp

body text

HTML body

attachments

message ID

thread ID (if available)

These messages are stored in the **Message object**.

---

### **Ingestion Responsibilities**

The ingestion system must:

Deduplicate messages

Maintain thread integrity

Detect new conversations

Update existing conversations

---

# **13.3 Conversation Builder**

### **Purpose**

Convert individual messages into conversation threads.

This step constructs the **Conversation object**.

---

### **Conversation Rules**

Messages are grouped based on:

provider thread ID

subject similarity

participant overlap

reply chain references

This ensures emails appear as threads rather than isolated messages.

---

### **Conversation Updates**

When a new message arrives:

message added to conversation

latest\_message\_timestamp updated

message\_count updated

The conversation then triggers the **AI interpretation pipeline**.

---

# **13.4 AI Interpretation Pipeline**

### **Purpose**

Transform raw email content into structured signals for the card interface.

AI processes the conversation to produce:

intent

quote

status

risk score

promotion classification

---

### **Inputs**

The AI system receives:

latest message

prior conversation context

sender identity

attachments

email metadata

---

### **Processing Steps**

The interpretation pipeline runs several tasks.

Intent extraction

Quote selection

Status classification

Promotion detection

Scam detection

These outputs are stored in the **Conversation metadata**.

---

### **Processing Triggers**

AI interpretation runs when:

new message arrives

conversation changes

thread reopened for discussion

---

# **13.5 Marketing Email Detection**

### **Purpose**

Determine whether the email is promotional.

This classification affects **card presentation**.

---

### **Detection Signals**

Signals may include:

bulk sending patterns

newsletter formatting

unsubscribe links

marketing language

brand domain recognition

---

### **Output**

If classified as promotion:

promotion\_flag \= true

This changes the card body behavior.

Instead of rendering an AI intent card, the system shows:

the first 1:1 section of the HTML email

This preserves the marketing email’s visual design.

---

# **13.6 Scam Detection Pipeline**

### **Purpose**

Identify suspicious emails and protect users.

---

### **Risk Signals**

The system analyzes signals such as:

domain impersonation

brand mismatch

urgent financial requests

link anomalies

known phishing patterns

---

### **Output**

The scam detection system generates:

risk\_score

potential\_scam\_flag

risk\_reasoning

If the threshold is exceeded:

status \= Potential scam

Detailed reasoning is stored for the **discussion system**.

---

# **13.7 Card Generation Service**

### **Purpose**

Convert conversation metadata into a UI-ready **card object**.

---

### **Card Elements**

Each card includes:

sender display

relationship signal or unsubscribe

intent

quote

status

carousel items

actions

---

### **Carousel Construction**

Carousel items are generated based on conversation content.

Standard emails:

1\. Intent card

2\. Attachment preview(s)

3\. Open full email

Marketing emails:

1\. First 1:1 section of HTML email

2\. Attachment preview(s), if present

3\. Open full email

---

### **Output**

The card is stored and passed to the **feed ranking system**.

---

# **13.8 Feed Ranking System**

### **Purpose**

Determine card ordering within the feed.

---

### **Ranking Modes**

Two ranking strategies exist.

Chronological

Relevance

---

### **Chronological Ranking**

Cards are ordered by:

latest\_message\_timestamp

---

### **Relevance Ranking**

Cards are ranked based on signals such as:

status

relationship strength

conversation recency

promotion classification

risk indicators

user interaction history

The ranking engine generates a **ranking score**.

Cards are sorted by this score in the relevance feed.

---

# **13.9 Discussion System**

### **Purpose**

Support AI conversations about emails.

Each conversation includes a persistent **discussion thread**.

---

### **Discussion Architecture**

When a user opens discussion:

discussion context loads

AI system receives conversation data

AI responses generated

discussion stored for future sessions

---

### **Discussion Context**

AI discussion uses:

full email thread

intent

quote

status

attachments

prior discussion history

---

### **Proactive Comments**

In certain scenarios the system generates **initial AI discussion messages**.

Triggers may include:

scam detection

long message

recurring conversation

attachment-heavy email

survey request

These comments appear when the user opens discussion.

---

# **13.10 Action Processing System**

### **Purpose**

Process user actions performed on cards.

Examples include:

reply

archive

save

delete

unsubscribe

block sender

report scam

---

### **Action Effects**

Actions update system state.

Example:

archive → conversation removed from feed

save → conversation flagged as saved

unsubscribe → sender hidden from feed

These updates may also influence feed ranking.

---

# **13.11 Real-Time Updates**

### **Purpose**

Ensure the inbox reflects new emails quickly.

---

### **Update Events**

Feed updates occur when:

new message arrives

conversation status changes

user actions occur

The system recalculates:

conversation metadata

card content

feed ranking

The UI refreshes automatically.

---

# **13.12 Performance Requirements**

For the system to feel responsive:

Key operations must remain fast.

Target expectations:

Email ingestion: near real-time

Card generation: \< 1 second

Feed refresh: \< 500ms

Discussion response: conversational speed

Slow interpretation should never block feed updates.

Fallback behavior should always allow users to open the full email thread.

---

# **13.13 Reliability and Fault Handling**

The system must tolerate failures gracefully.

Examples include:

AI interpretation failure

temporary API outages

message ingestion delays

Fallback behaviors include:

display raw email preview

allow full thread access

retry interpretation

queue background processing

The user must never lose access to their email content.

---

# **Section 13 Summary**

The system architecture includes five primary pipelines:

Email ingestion

Conversation construction

AI interpretation

Card generation

Feed ranking

Discussion assistance

These systems work together to transform raw email into:

interpreted conversation cards

AI-assisted discussions

prioritized inbox feeds

The architecture ensures the product remains:

fast

reliable

transparent

while enabling the AI-powered inbox experience.

---

The next section would be **Section 14: Trust, Safety, and Privacy**, which is extremely important for an AI-powered email product.

# **Section 14: Trust, Safety, and Privacy**

## **Section 14: Trust, Safety, and Privacy**

This section defines **how the product protects user data, maintains trust, and prevents harmful outcomes**.

Email is one of the **most sensitive personal data surfaces** people have. It includes:

Financial information

Travel records

Legal documents

Private conversations

Medical communication

Work discussions

Because the product introduces **AI interpretation**, trust and safety must be designed deliberately.

This section defines safeguards across:

User privacy

AI transparency

Scam protection

Security architecture

User control

System abuse prevention

---

# **14.1 Core Trust Principles**

The product must follow several foundational principles.

### **1\. User Ownership**

Users own their email data.

The system only processes emails to deliver product functionality.

---

### **2\. Transparent Interpretation**

Whenever AI interprets email content, the system must show **evidence**.

The product accomplishes this through:

Quotes supporting intent

Open thread access

Discussion explanations

Users should always be able to verify the AI interpretation.

---

### **3\. No AI Communication Autonomy**

The AI system **never sends email automatically**.

AI can:

Explain emails

Summarize threads

Help draft replies

Identify risks

AI cannot:

Send messages

Reply automatically

Interact with external senders

This prevents unintended automated communication loops.

---

### **4\. User Override**

Users must always be able to override AI judgments.

Examples include:

Ignoring scam warnings

Opening full threads

Responding manually

Disabling relevance feed

Automation assists but does not control the user.

---

# **14.2 Data Privacy**

### **Data Sensitivity**

Email content includes extremely sensitive information.

The system must treat email as **private user data**.

---

### **Data Handling Rules**

The system must ensure:

Encrypted data transmission

Secure storage of messages

Limited internal access

Strict permission boundaries

Email content should only be accessed by the systems required to provide functionality.

---

### **Data Minimization**

Only necessary data should be processed.

Examples:

message body

sender

attachments

thread context

Non-essential metadata should not be retained.

---

# **14.3 AI Privacy Safeguards**

Because AI systems process email content, additional safeguards are required.

### **Isolation**

User emails must be processed in isolation.

One user’s emails should never influence another user’s interpretation.

---

### **Training Restrictions**

User email content must **not automatically be used to train models**.

If training data is collected in the future, it must require:

explicit user consent

clear opt-in

anonymization safeguards

---

### **Temporary Processing**

Where possible, AI processing should rely on:

temporary inference pipelines

ephemeral context

minimal storage of intermediate outputs

---

# **14.4 Scam Protection**

The system actively protects users from phishing and scams.

Scam protection includes:

risk detection

AI explanations

user reporting

sender blocking

---

### **Risk Indicators**

When a message crosses a risk threshold, the card displays:

⚠ Potential scam

This provides a clear visual warning.

---

### **Explanation Layer**

If the user opens discussion, the AI explains the risk signals.

Example:

The sender claims to be Amazon, but the email domain does not match Amazon's official domain.

The message also asks for urgent account verification through a link.

This approach teaches users **how scams work**, not just that a message is suspicious.

---

### **User Reporting**

Users can report scams directly.

Reported scams may improve future scam detection.

---

# **14.5 Sender Controls**

Users must be able to control who appears in their inbox.

Available controls include:

block sender

hide sender

unsubscribe

mute thread

These actions allow users to reclaim control of their inbox.

---

# **14.6 Marketing Email Control**

Marketing emails are one of the largest sources of inbox frustration.

The product helps users manage them through:

promotion detection

unsubscribe visibility

local unsubscribe

promotion ranking demotion

---

### **Local Unsubscribe**

Even if companies ignore unsubscribe requests, users can still remove them from the feed.

The system hides future messages from the sender.

This restores **user control over subscription noise**.

---

# **14.7 AI Explanation Transparency**

AI interpretation must remain explainable.

Key transparency features include:

Quote supporting intent

Discussion explanations

Open thread access

Users should never feel the AI is making **invisible decisions**.

---

# **14.8 User Control of AI Features**

Users must be able to control AI features.

Possible controls include:

Disable relevance feed

Disable proactive AI comments

Disable AI discussion assistant

Switch to chronological feed

The product should function even with minimal AI assistance.

---

# **14.9 Abuse Prevention**

Because the product processes external email content, safeguards must exist against abuse.

Examples include:

malicious email payloads

phishing links

spam floods

social engineering attempts

Defensive measures include:

link safety analysis

attachment scanning

domain reputation checks

sender anomaly detection

---

# **14.10 Data Breach Mitigation**

In the event of a security incident, the system must limit exposure.

Safeguards include:

strong encryption

segmented data storage

access logging

intrusion detection

Sensitive information should never be stored unnecessarily.

---

# **14.11 User Trust Signals**

To maintain trust, the product should clearly communicate:

what AI is doing

why a message was flagged

how unsubscribe works

how user data is handled

Examples of visible trust signals include:

Scam reasoning explanations

Intent quotes

Discussion transparency

Explicit unsubscribe confirmation

---

# **14.12 Failure Transparency**

When the system is uncertain, it should communicate that uncertainty.

Example:

This message may be suspicious, but the signals are inconclusive.

Avoiding overconfidence helps preserve user trust.

---

# **Section 14 Summary**

Trust and safety systems protect users across several layers:

Privacy protection

AI transparency

Scam detection

Sender controls

Marketing control

User override

Security safeguards

These protections ensure the product remains:

safe

transparent

user-controlled

while still delivering the benefits of AI-assisted email.

---

The next section would be **Section 15: Metrics and Success Criteria**, which defines how we evaluate whether the product actually solves the inbox problems it set out to fix.

# **Section 15: Metrics and Success Criteria**

## **Section 15: Metrics and Success Criteria**

This section defines **how the product will be evaluated**.

Metrics must answer one fundamental question:

Does this product actually make email easier to deal with?

Success is not measured by time spent in the product or engagement loops.

The product’s goal is the opposite:

Help users process their inbox quickly and return to their lives.

Metrics therefore focus on:

Inbox clarity

Speed of decision-making

Spam and scam reduction

User trust

Email control

---

# **15.1 North Star Metric**

The most important metric should reflect the core product promise.

### **North Star**

Time to inbox resolution

Definition:

The average time it takes a user to process all new emails in a session.

This includes actions such as:

Reply

Archive

Delete

Unsubscribe

Save

The goal is to reduce the **cognitive and time cost of email triage**.

---

# **15.2 Key Product Metrics**

Several additional metrics measure different aspects of product value.

---

## **1\. Inbox Processing Speed**

Measures how quickly users resolve incoming emails.

Example metric:

Average time to process an email card

Healthy outcomes:

Most emails resolved in a few seconds

Minimal thread openings required

---

## **2\. Card Resolution Rate**

Measures how often emails are handled **without opening the full thread**.

Example metric:

% of emails resolved directly from the card

A high rate indicates the card system is working effectively.

---

## **3\. Discussion Utility**

Measures whether AI discussion actually helps users understand emails.

Example metrics:

% of discussions that lead to a user action

Average discussion length

User satisfaction after discussion

A good system helps users **resolve uncertainty quickly**.

---

## **4\. Scam Prevention**

Measures how effectively the product protects users.

Possible metrics include:

% of flagged scams deleted

% of scams reported

False positive scam rate

A strong system should both detect scams and maintain user trust.

---

## **5\. Unsubscribe Success**

Measures whether users can reduce marketing noise.

Example metrics:

Number of unsubscribe actions per user

Reduction in promotion emails over time

The product should help users reclaim control over subscription spam.

---

## **6\. Feed Mode Usage**

Measures how users interact with ranking modes.

Metrics include:

% of users using relevance feed

% of users switching back to chronological

This helps determine whether the ranking system is trusted.

---

## **7\. Email Resolution Completion**

Measures whether users actually finish processing their inbox.

Example metric:

% of sessions reaching feed completion

Feed completion means:

User reaches end of inbox feed

A high completion rate suggests the product reduces inbox overwhelm.

---

# **15.3 AI Performance Metrics**

Because AI is central to the product, its performance must be measured.

---

## **Intent Accuracy**

Measures whether the intent correctly reflects the email.

Possible evaluation methods:

Human review sampling

User correction signals

Discussion clarification frequency

The goal is that intent feels **obviously correct most of the time**.

---

## **Quote Relevance**

Measures whether the quote clearly supports the intent.

A good quote should make users feel:

Yes, that is what the email is about.

---

## **Scam Detection Accuracy**

Evaluates both:

True positive detection

False positive rate

Too many false positives would reduce trust.

Too many missed scams reduces protection.

---

## **Promotion Classification Accuracy**

Measures whether marketing emails are correctly detected.

This impacts:

unsubscribe surfacing

feed ranking

card presentation

Misclassification could harm the user experience.

---

# **15.4 Trust and Safety Metrics**

Trust is critical for an AI email product.

Metrics should monitor:

User trust in scam detection

User trust in AI interpretations

User confidence in discussion responses

Potential signals include:

User overrides of AI decisions

User reports of incorrect scam labels

User reliance on discussion assistant

---

# **15.5 User Satisfaction Metrics**

User perception matters as much as algorithmic accuracy.

Possible measures include:

Inbox stress reduction

Perceived spam reduction

Confidence identifying scams

Clarity of email interpretation

Survey prompts may include:

Email feels easier to manage

I trust the system to identify suspicious messages

I can quickly understand what emails mean

---

# **15.6 Retention Metrics**

Retention measures whether the product becomes part of daily life.

Important signals include:

Daily active users

Weekly active users

Session frequency

Inbox sessions per day

A healthy product likely becomes a **daily tool**.

---

# **15.7 Product Health Metrics**

Operational metrics ensure the system performs reliably.

Examples include:

Email sync success rate

AI interpretation latency

Feed refresh latency

Discussion response time

These metrics ensure the product feels responsive.

---

# **15.8 Negative Signals**

The system must monitor indicators that something is wrong.

Examples include:

Users abandoning sessions early

Users switching away from relevance feed

Users ignoring scam warnings

Users disabling AI features

These signals help identify friction points.

---

# **15.9 Long-Term Impact Metrics**

Over time, the product should improve the overall quality of users’ inboxes.

Possible long-term indicators include:

Reduction in promotion emails

Reduction in spam exposure

Higher response rate to important emails

Lower time spent managing email

These metrics measure whether the system truly improves email as a communication medium.

---

# **Section 15 Summary**

Product success will be evaluated through metrics focused on:

Inbox processing speed

AI interpretation accuracy

Spam and scam reduction

User trust

Email control

The most important outcome is:

Users feel their inbox is understandable and manageable again.

---

If you’d like, the next step could be **Section 16: Product Roadmap**, which would outline how this product launches and evolves from MVP to a full platform.

# **Section 16: Product Roadmap**

## **Section 16: Product Roadmap**

This section defines **how the product evolves over time**.

The roadmap is designed around a simple principle:

Solve the inbox triage problem first.

Expand intelligence second.

Build a relationship system third.

Trying to build everything at once would create unnecessary complexity.

The roadmap therefore progresses through **four phases**:

Phase 1 — Feed Inbox (MVP)

Phase 2 — AI Interpretation Layer

Phase 3 — Relationship Intelligence

Phase 4 — Email Control Platform

Each phase unlocks a new layer of value.

---

# **16.1 Phase 1: Feed Inbox (MVP)**

### **Goal**

Prove that **a feed-based inbox is faster and easier to process than traditional email lists**.

This phase focuses on the core interaction:

Scan → decide → move on

---

### **Core Features**

The MVP includes:

Email account connection

Conversation-based feed

Conversation cards

Intent \+ quote extraction

Carousel card structure

Reply

Discuss

Forward

Save

Archive

Thread view

Chronological feed

Basic relevance feed

Promotion detection

Unsubscribe action

Local unsubscribe filtering

Marketing emails display:

first 1:1 section of their HTML design

rather than an AI intent card.

---

### **MVP Success Criteria**

Phase 1 succeeds if users can:

Process inbox faster

Understand emails from the card

Unsubscribe quickly

Resolve most emails without opening threads

---

### **Why This Phase Matters**

If this phase fails, nothing else matters.

The feed interaction must prove it is **fundamentally better than traditional inboxes**.

---

# **16.2 Phase 2: AI Interpretation Layer**

### **Goal**

Make the inbox **explain itself**.

This phase strengthens the AI layer.

---

### **Features Introduced**

Improved intent detection

More accurate quote extraction

Status classification improvements

Scam detection system

Risk explanations

Proactive AI discussion comments

Thread summaries

Attachment interpretation

AI becomes a **reasoning assistant for email**.

---

### **Example Improvements**

Users begin seeing proactive insights like:

This email may be a phishing attempt.

or

This thread has 6 messages and they are waiting for your reply.

---

### **Success Criteria**

Users begin using discussion to:

Understand confusing emails

Confirm scam suspicions

Summarize long threads

Decide how to reply

---

# **16.3 Phase 3: Relationship Intelligence**

### **Goal**

Transform email from **message management** into **relationship awareness**.

This phase introduces the concept of a **Relationship Hub**.

---

### **Relationship Hub**

Each sender becomes a profile-like object.

Users can see:

All conversations with a person

Interaction history

Relationship strength

Shared attachments

Discussion history

This makes email less about individual messages and more about **ongoing relationships**.

---

### **Additional Features**

Relationship ranking signals

Frequent contacts detection

Opportunity signal detection

Contact intelligence

Conversation history summaries

Example insight:

You last spoke with this recruiter 3 weeks ago.

---

### **Why This Matters**

Most email value comes from **people**, not messages.

The relationship system makes that structure visible.

---

# **16.4 Phase 4: Email Control Platform**

### **Goal**

Give users **complete control over what reaches them**.

This phase expands beyond triage into **inbox defense**.

---

### **Features Introduced**

Advanced scam detection

Sender reputation scoring

Subscription management dashboard

Automated unsubscribe attempts

Email frequency control

Brand notification management

Users gain visibility into:

Who sends them email

How often

Why

---

### **Subscription Control System**

Users can manage marketing relationships directly.

Example capabilities:

Pause brand emails

Limit email frequency

Remove subscriptions

The system becomes a **control layer for email subscriptions**.

---

# **16.5 AI Agent Capabilities (Future)**

Later versions may introduce limited agent functionality.

Possible examples:

Attempt unsubscribe flows automatically

Extract data from receipts

Track travel changes

Detect contract terms

These features would be carefully constrained.

The system must never become:

AI sending emails to AI

Users remain in control of communication.

---

# **16.6 Monetization Strategy**

The roadmap also enables a sustainable business model.

Possible revenue models include:

### **Premium Subscription**

Paid users receive:

Ad-free inbox

Advanced scam detection

AI reasoning upgrades

Subscription management tools

Relationship intelligence features

---

### **Platform Advertising (Optional)**

Free users may see:

sponsored newsletter recommendations

brand discovery placements

These would appear as feed cards.

Importantly:

Marketing emails are already treated like feed content.

This makes the advertising format natural.

---

# **16.7 Long-Term Vision**

If the roadmap succeeds, the product becomes more than an email client.

It becomes a system that helps users:

Understand communication

Control subscriptions

Avoid scams

Manage relationships

Email transforms from a chaotic inbox into:

a structured decision feed

---

# **Section 16 Summary**

The roadmap evolves through four phases:

Phase 1 — Feed inbox

Phase 2 — AI interpretation

Phase 3 — Relationship intelligence

Phase 4 — Email control platform

Each phase builds on the previous one while keeping the core goal constant:

Make email understandable, controllable, and fast to process.

---

If you’d like, the next thing we could do (and this is extremely useful) is:

**Section 17: Competitive Landscape**

Because this product sits in a space with:

* Superhuman

* Spark

* Gmail

* Hey

* Outlook

* AI assistants

…and understanding **why this product wins** will sharpen the idea a lot.

# **Section 17: Competitive Landscape**

## **Section 17: Competitive Landscape**

This section evaluates **existing email products and adjacent solutions**.

The goal is not simply to list competitors. It is to understand:

What problem each product solves

Where they fall short

Why Decision Inbox is different

The landscape can be grouped into **four categories**:

Traditional email clients

Speed-focused email tools

Opinionated email redesigns

AI assistants

Decision Inbox introduces a **fifth category**:

AI-interpreted inbox

---

# **17.1 Traditional Email Clients**

Examples include:

* Gmail

* Outlook

* Yahoo Mail

These platforms dominate global email usage.

---

### **Core Model**

Traditional clients present email as:

Chronological message lists

Users must open emails to understand:

What it means

Whether it matters

What action is required

---

### **Strengths**

Reliable infrastructure

Deep ecosystem integration

Strong spam filtering

Mass adoption

---

### **Weaknesses**

High cognitive load

Little interpretation of email meaning

Inbox clutter from marketing messages

Limited help understanding threads

Users still must manually decide:

Is this important?

What does this email want?

---

### **Key Gap**

Traditional inboxes **organize messages**, but they do not help users **understand them**.

---

# **17.2 Speed-Focused Email Tools**

Examples include:

* Superhuman

* Spark Mail

These tools focus on **speed and efficiency**.

---

### **Core Model**

Speed-focused tools improve email workflows through:

Keyboard shortcuts

Fast triage tools

Automation rules

Snoozing and reminders

---

### **Strengths**

Fast email processing

Professional productivity features

Strong UI design

---

### **Weaknesses**

Still based on traditional inbox structure

Users must still interpret email meaning

Limited spam or subscription control

These tools help users process email **faster**, but they do not reduce the **mental effort of interpretation**.

---

### **Key Gap**

They optimize workflow speed rather than **clarity of communication**.

---

# **17.3 Opinionated Email Redesigns**

Examples include:

* HEY Email

These products attempt to rethink the inbox experience.

---

### **Core Model**

HEY introduces concepts such as:

Screening senders

Imbox vs Feed

Newsletter separation

---

### **Strengths**

Strong philosophy about inbox control

Improved spam filtering

Cleaner inbox experience

---

### **Weaknesses**

Rigid workflow

Limited AI interpretation

Does not help understand complex emails

The product primarily solves **subscription overload**.

It does not solve **interpretation complexity**.

---

### **Key Gap**

HEY focuses on **who gets into your inbox**, not **what emails mean**.

---

# **17.4 AI Assistants**

Examples include:

* Google Gemini

* Microsoft Copilot

These systems bring AI capabilities into productivity software.

---

### **Core Model**

AI assistants typically function as:

Chat interfaces

Email summarizers

Draft generators

Users must manually trigger AI assistance.

---

### **Strengths**

Powerful summarization

Strong drafting capabilities

General intelligence

---

### **Weaknesses**

AI lives outside the inbox interface

Requires manual prompting

Limited structural redesign of email experience

These tools add AI **on top of email**, but they do not redesign the inbox itself.

---

### **Key Gap**

AI is **reactive rather than structural**.

---

# **17.5 Where Decision Inbox Fits**

Decision Inbox introduces a new category:

AI-interpreted inbox

Instead of organizing messages or accelerating workflows, it focuses on:

Understanding communication

Reducing cognitive load

Protecting users from scams

Controlling subscriptions

---

### **Core Difference**

Traditional email clients show:

Messages

Decision Inbox shows:

Decisions

Each card answers three questions immediately:

What is this email about?

Why does the AI think that?

What should I do about it?

---

# **17.6 Competitive Comparison**

| Product | Core Idea | Strength | Weakness |
| ----- | ----- | ----- | ----- |
| Gmail | Default email platform | Massive ecosystem | Inbox overload |
| Outlook | Enterprise email client | Enterprise integration | Complex interface |
| Superhuman | Fast email workflow | Speed and shortcuts | Still message-centric |
| Spark | Smart inbox features | Helpful categorization | Limited interpretation |
| HEY | Inbox filtering philosophy | Strong spam control | Rigid structure |
| Gemini / Copilot | AI assistant | Powerful language AI | Not integrated into inbox design |
| Decision Inbox | AI-interpreted feed | Email understanding | Requires new interface adoption |

---

# **17.7 Strategic Advantage**

Decision Inbox combines three ideas competitors treat separately:

Inbox control

AI interpretation

Feed-style interface

This combination produces a fundamentally different experience.

Instead of:

reading email

users primarily:

scan meaning

make decisions

move on

---

# **17.8 Strategic Risk**

The largest competitive risk is that **existing platforms integrate similar AI capabilities**.

For example:

* Gmail could introduce AI-generated email summaries

* Outlook could add automated prioritization

However, these systems are constrained by legacy inbox structures.

Decision Inbox is designed **from the ground up** around AI interpretation.

---

# **17.9 Market Opportunity**

Email is one of the largest digital communication systems in the world.

Key indicators include:

4+ billion global email users

Hundreds of billions of emails sent daily

Widespread frustration with spam and marketing overload

Increasing sophistication of phishing attacks

Despite this scale, the inbox experience has changed very little in decades.

---

# **Section 17 Summary**

Existing email products fall into four categories:

Traditional email clients

Speed-focused email tools

Opinionated inbox redesigns

AI assistants

Decision Inbox introduces a new category:

AI-interpreted inbox

The product’s advantage comes from combining:

Feed interface

Conversation-level thinking

AI interpretation

Subscription control

Scam protection

This approach shifts email from **message management** to **decision support**.

---

If you’d like, the next section that would sharpen this even further is:

**Section 18: Product Risks and Failure Modes**

Because the biggest challenge for this product is not building it.

It’s making sure the idea **actually works in the real world.**

# **Section 18: Product Risks and Failure Modes**

## **Section 18: Product Risks and Failure Modes**

This section identifies **where the product could fail**.

Every ambitious product has assumptions. The purpose of this section is to surface the biggest ones and understand:

What could go wrong

Why it might happen

How to mitigate it

For Decision Inbox, the major risks fall into five categories:

AI interpretation risk

User trust risk

Interface adoption risk

Email ecosystem risk

Business model risk

---

# **18.1 AI Interpretation Risk**

### **Risk**

The AI may interpret emails incorrectly.

Examples:

Intent is wrong

Quote does not support intent

Status misclassified

Promotion incorrectly detected

If this happens frequently, the core interface breaks.

Users will stop trusting the card.

---

### **Why This Matters**

The entire interface depends on **AI interpretation being reliable**.

If users feel the AI is wrong often, they will revert to:

Opening every email

which removes the product’s advantage.

---

### **Mitigation**

Several safeguards reduce this risk.

Quote anchors interpretation

Open thread always accessible

Discussion layer explains reasoning

Intent kept short and humble

Users should always be able to **verify the AI interpretation quickly**.

---

# **18.2 Scam Detection Risk**

### **Risk**

The system may incorrectly classify emails as scams.

False positives could cause users to distrust the system.

Example:

A legitimate bank email flagged as suspicious

---

### **Why This Matters**

Trust is extremely fragile in security systems.

If users feel scam detection is unreliable, they may:

Ignore warnings entirely

---

### **Mitigation**

Safeguards include:

Clear explanation of risk signals

Discussion layer for reasoning

Cautious labeling ("Potential scam")

User override capability

The system should act as **an advisor, not a gatekeeper**.

---

# **18.3 Feed Interface Risk**

### **Risk**

Users may find the feed model unfamiliar.

Traditional inboxes have looked the same for decades:

Sender

Subject

Preview text

Switching to cards and carousel previews introduces a new interaction model.

---

### **Possible Failure**

Users may initially feel:

Disoriented

Slower

Uncertain how to process email

---

### **Mitigation**

The interface must remain:

Predictable

Simple

Consistent

Key design choices supporting this include:

Consistent action row

Finite feed

Chronological fallback

Simple card structure

The experience should feel like **an easier inbox**, not a radically different one.

---

# **18.4 AI Overreach Risk**

### **Risk**

The AI system could become intrusive.

Examples:

Too many proactive comments

Overly verbose explanations

Unnecessary AI involvement

This would create the feeling that the inbox is filled with **AI noise**.

---

### **Mitigation**

Strict rules for proactive AI:

Only comment when risk or confusion exists

Keep comments short

Place comments in discussion layer

Never clutter the feed

The AI should feel like a **quiet expert available when needed**.

---

# **18.5 Marketing Email Detection Risk**

### **Risk**

Promotion detection may incorrectly classify emails.

Possible issues:

Important brand email treated as promotion

Marketing email treated as personal

Misclassification could affect feed ranking and presentation.

---

### **Mitigation**

Safeguards include:

Allow user overrides

Easy unsubscribe or re-enable

Promotion ranking adjustable through behavior

The system should learn from user interaction patterns.

---

# **18.6 Interface Density Risk**

### **Risk**

The card may contain too much information.

Card elements include:

Sender

Relationship signal

Intent

Quote

Status

Carousel

Actions

If poorly designed, the card could feel visually heavy.

---

### **Mitigation**

Design principles must prioritize:

Whitespace

Visual hierarchy

Short intent text

Short quotes

The card should be **scannable in under a second**.

---

# **18.7 AI Discussion Dependency Risk**

### **Risk**

Users may become overly dependent on AI discussion to interpret email.

If discussion becomes necessary for many emails, the product fails.

The feed should resolve most cases.

---

### **Mitigation**

Design rule:

Discussion is optional support, not a primary interface.

Most emails should be understandable directly from the card.

---

# **18.8 Email Ecosystem Risk**

### **Risk**

Email providers could introduce competing features.

Examples include:

* Gmail integrating AI summaries

* Outlook adding AI prioritization

* platform-level unsubscribe management

Because providers control the underlying infrastructure, they have advantages.

---

### **Mitigation**

The product differentiates through:

Feed interface

Conversation-first model

Integrated AI reasoning

Subscription control

Providers may add AI features, but redesigning the inbox structure is harder.

---

# **18.9 Data Privacy Risk**

### **Risk**

Users may hesitate to allow AI systems access to their email.

Email is highly personal data.

Concerns may include:

data misuse

AI training on private emails

security breaches

---

### **Mitigation**

Strong privacy policies must be visible and clear.

Safeguards include:

No automatic model training on user emails

Encrypted storage

Transparent AI processing

User control over AI features

Trust must be earned explicitly.

---

# **18.10 Business Model Risk**

### **Risk**

Monetization could conflict with the product’s promise of inbox clarity.

If ads become too aggressive, the product risks recreating the same clutter it aims to remove.

---

### **Mitigation**

Monetization should prioritize:

premium subscriptions

optional ad surfaces

respectful ad placement

Ads should never overwhelm the inbox experience.

---

# **18.11 Product Complexity Risk**

### **Risk**

The system includes many components:

AI interpretation

feed ranking

discussion assistant

scam detection

subscription management

If poorly integrated, the product may feel complicated.

---

### **Mitigation**

The interface should focus on **three simple actions**:

Scan

Decide

Move on

Everything else should remain secondary.

---

# **Section 18 Summary**

The most significant risks include:

AI interpretation errors

User trust breakdown

Feed interface adoption challenges

AI overreach

Privacy concerns

Platform competition

These risks can be mitigated through:

transparent AI

user control

simple interaction design

careful feature boundaries

If these safeguards hold, the product can deliver on its core promise:

Make email understandable again.

---

The next section would be **Section 19: Product Narrative**, which turns the entire spec into a **clear story of why this product exists and why it matters**.

# **Section 19: Product Narrative**

## **Section 19: Product Narrative**

This section explains **why this product should exist**.

A good product narrative answers three questions:

What is broken today?

Why hasn’t it been fixed?

Why does this solution work now?

The narrative should be simple enough that someone can understand the idea immediately, yet powerful enough that it feels inevitable once explained.

---

# **19.1 The Problem**

Email is one of the most important communication systems in the world.

Every day, billions of messages are sent through it. These messages include:

Work conversations

Personal communication

Receipts and financial records

Travel updates

Medical information

Legal documents

Despite this importance, the way we experience email has barely changed in decades.

Most inboxes still look like this:

Sender

Subject line

Preview text

Users must open emails just to understand:

What the email means

Whether it matters

What they should do about it

As a result, the modern inbox has become overwhelming.

People are buried under:

Marketing emails

Surveys

Shipping updates

Notifications

Scams

Important messages get mixed together with noise.

The inbox has effectively become a **junk drawer for digital communication**.

---

# **19.2 The Real Problem**

The problem is not simply the volume of email.

The real problem is **interpretation**.

Each email requires the user to perform a small cognitive task:

Read

Interpret

Decide

Over the course of a day, users repeat this process dozens or hundreds of times.

Even when an email is trivial, the user must still answer:

Is this important?

What does this person want?

Do I need to respond?

This constant micro-decision-making creates mental fatigue.

Email has become less about communication and more about **sorting and interpreting messages**.

---

# **19.3 Why Existing Solutions Haven’t Fixed It**

Many products have tried to improve email, but they focus on the wrong layer.

Traditional clients improve:

organization

search

spam filtering

Productivity-focused tools improve:

speed

keyboard shortcuts

workflow automation

AI assistants improve:

summarization

drafting replies

chat-based help

But all of these approaches keep the same underlying structure:

lists of messages

They help users move faster through the inbox, but they do not reduce the core problem:

Users still have to interpret every email themselves.

---

# **19.4 Why This Can Be Solved Now**

Recent advances in language models change what is possible.

For the first time, software can reliably understand:

intent

requests

tone

risk signals

conversation context

This means email can now be interpreted automatically.

Instead of showing users raw messages, a system can extract:

What the email is about

Why it matters

What action might be required

This makes it possible to redesign the inbox around **decisions instead of messages**.

---

# **19.5 The Core Idea**

Decision Inbox transforms email from a message list into a **decision feed**.

Each conversation appears as a card that answers three questions immediately:

What is this email about?

Why does the system think that?

What should I do about it?

The user can then decide quickly:

Reply

Archive

Ignore

Unsubscribe

Discuss with AI

Most emails can be resolved in seconds without opening the thread.

---

# **19.6 How the Experience Feels**

Instead of digging through an inbox, the user scrolls through a feed of conversations.

Each card surfaces the essential meaning of the email.

The user can quickly see:

A recruiter asking to schedule an interview

A package delivery update

A marketing promotion

A suspicious message pretending to be a bank

Marketing emails appear visually as they were designed, allowing users to recognize and skip them quickly.

Suspicious emails are flagged.

Complex threads can be discussed with an AI assistant.

The inbox becomes something that can actually be **processed and finished**.

---

# **19.7 The Product Philosophy**

The product is built around a simple idea:

Software should help people understand communication, not just store it.

Instead of forcing users to parse every message, the system extracts meaning and presents it clearly.

This reduces the mental overhead of managing email.

---

# **19.8 The Long-Term Vision**

If successful, the product changes how people experience email.

The inbox becomes:

clear

prioritized

safe

manageable

Users gain tools to:

remove unwanted subscriptions

identify scams

understand conversations quickly

control who reaches them

Email becomes less chaotic and more intentional.

---

# **19.9 Why This Matters**

Email remains one of the most important communication systems in the digital world.

Yet for many people, opening their inbox creates a feeling of stress.

A better inbox would mean:

Less time spent sorting messages

Less exposure to scams

Less marketing noise

More clarity about important conversations

Decision Inbox attempts to solve this problem at its root.

Instead of optimizing the inbox we inherited, it rethinks what an inbox should show in the first place.

---

# **Section 19 Summary**

The product narrative can be summarized simply:

Email today shows messages.

Decision Inbox shows meaning.

By combining:

AI interpretation

conversation-level thinking

feed-style interaction

subscription control

the inbox becomes something people can understand quickly and finish processing.

---

If you’d like, the **very last section worth writing** is **Section 20: The One-Sentence Product**, because forcing the entire product into a single sentence usually reveals whether the idea is actually sharp enough.

# **Section 20: The One-Sentence Product**

## **Section 20: The One-Sentence Product**

This section distills the entire product into **its simplest possible form**.

A strong product can usually be described in one clear sentence that answers:

What it is

Who it is for

What problem it solves

If the sentence is unclear or overly complex, the product idea usually is too.

---

# **20.1 The Core Sentence**

The clearest expression of the product is:

Decision Inbox is an AI-powered email client that turns your inbox into a feed of conversations you can understand and resolve instantly.

This sentence communicates three essential ideas:

AI-powered

Email client

Decision-focused inbox

---

# **20.2 Alternative One-Sentence Versions**

Different audiences may resonate with slightly different phrasing.

---

### **Version 1: Problem-focused**

Decision Inbox helps people understand and process email instantly by turning their inbox into an AI-interpreted conversation feed.

---

### **Version 2: Simpler framing**

Decision Inbox is an email client that explains what emails mean so you can decide what to do without reading everything.

---

### **Version 3: Vision framing**

Decision Inbox replaces the traditional message list with an AI-interpreted feed that helps you understand and manage communication faster.

---

# **20.3 Investor-Style Framing**

When describing the product in a fundraising context, the sentence may emphasize the shift in category.

Example:

Decision Inbox is an AI-interpreted inbox that turns email from a list of messages into a feed of decisions.

This version highlights the **category creation** aspect of the product.

---

# **20.4 The Mental Model**

Another way to express the idea is through a comparison.

Email today is a list of messages.

Decision Inbox is a feed of conversations.

Or more specifically:

Traditional email shows what was sent.

Decision Inbox shows what it means.

These comparisons help people quickly understand the difference.

---

# **20.5 The Product in Three Words**

If the product had to be summarized even further, the idea can be reduced to:

Interpreted email inbox

or

Decision-based inbox

These phrases capture the core shift the product introduces.

---

# **Section 20 Summary**

The entire product can ultimately be expressed as:

Decision Inbox is an AI-powered email client that turns your inbox into a feed of conversations you can understand and resolve instantly.

Everything in the specification exists to make that sentence true.

# **Tab 21**

# **Product Decisions**

Grounding in your product.

Decision Inbox reframes email as **a feed of decisions instead of a list of messages**.

Below is the same decision summary, structured with the **main decision as H1** and supporting decisions as **H2s**.

---

# Every Email Card Shows One Recommended Action

The system interprets each email and surfaces **the single most likely next action for the user**.

The card answers:

**“What should I do next?”**

Examples:

Reply to Bobby Chen

Pay invoice

Sign document

Add ticket to Apple Wallet

Confirm meeting

Unsubscribe from Nike

No action required

The recommended action becomes the **primary signal of the card**, helping users understand the meaning of the email without opening it.

---

## **Emails May Contain Multiple Possible Actions**

Many emails imply more than one action.

Example flight email:

Possible actions

Check in

Add boarding pass to wallet

View flight details

Change seat

The system will:

1. Detect all plausible actions  
2. Rank them  
3. Surface **only one recommended action**

The remaining actions are not shown on the card.

Mental model:

**recommended decision, not full capability list**

---

## **Actions Are Ranked Using Email Semantics**

The system determines the best action by interpreting the **meaning of the email**.

Signals include:

* sender intent  
* request language  
* urgency signals  
* contextual cues

Example:

Email says:

“Please sign the attached document before Friday.”

Possible actions:

View attachment

Download document

Sign document

Recommended action:

Sign document

Because it best reflects the **goal of the message**.

---

## **When No Clear Action Exists, The Card Says “No Action Required”**

Some emails do not require a user decision.

Examples:

* thank-you emails  
* announcements  
* informational updates  
* newsletters  
* automated notifications

In these cases the card shows:

No action required

This prevents the system from inventing artificial actions.

---

## **Recommended Actions Are Labels, Not Buttons**

Recommended actions are **descriptive labels** that explain what the email implies.

Examples:

Review proposal

Prepare presentation

Discuss strategy

Bring documents to appointment

The system clarifies the **decision implied by the message**, even if the product cannot perform the action directly.

Mental model:

**decision guidance, not automation**

---

## **Some Actions May Be Elevated When Direct Execution Exists**

If the email contains a link that directly fulfills the action, the system may elevate it.

Examples:

Reply to Bobby Chen

Unsubscribe from Nike

Add boarding pass to Apple Wallet

Sign document

These could become interactive affordances when possible, but the primary goal remains **clarity of intent**.

---

## **The Action Vocabulary Will Stabilize Over Time**

The system initially generates actions dynamically.

Process:

1. AI proposes actions based on email meaning  
2. The system checks if a similar action already exists  
3. Existing actions are reused when possible  
4. New actions are created when necessary

Over time, the system converges toward a **stable set of action language**.

Likely core verbs include:

Reply

Pay

Sign

Confirm

Add

View

Download

Track

Unsubscribe

This creates consistency across the inbox while allowing the system to evolve.

---

## **The Inbox Becomes a Decision Feed**

Instead of showing metadata like subject lines and previews, the feed surfaces **the decisions implied by emails**.

Example inbox:

Reply to Bobby Chen

Pay invoice

Sign document

Add boarding pass to Apple Wallet

Confirm meeting

Unsubscribe from Nike

No action required

Each card helps the user understand and resolve email faster without opening the thread.

---

## **Final System Model**

Email

↓

Interpret meaning

↓

Detect possible actions

↓

Rank actions using semantics

↓

Surface one recommended action

Displayed on the card alongside:

* Sender  
* Intent  
* Quote  
* Recommended Action

This structure operationalizes the core shift of the product: turning email from **messages to decisions**.

# **Updated Card Spec**

# **Email Card System Spec (Corrected)**

## **Core Principle**

Each card answers:

**“What is this, and what should I do with it?”**

Structure:

1. Trust Layer (Header)  
2. Content Layer (Subject \+ Quote \+ Summary)  
3. Action Surface (Unified)

---

# **1\. Trust Layer (Header)**

### **Purpose**

Verification \+ recognition

### **Fields**

* Sender Name  
* Email Address  
* Time (relative)  
* CardTag (Relationship / Unsubscribe)

### **Rules**

* Email address is always visible  
* Time is always relative  
* CardTag appears only when relevant  
* Subject is NOT part of this layer

---

# **2\. Content Layer (Body)**

### **Purpose**

Make the email instantly scannable

---

## **2.1 Subject**

### **Definition**

* First element in the content layer  
* Positioned above the quote

### **Role**

* Recognition anchor  
* Matches how users traditionally identify emails

### **Rules**

* Always present  
* Treated as content, not metadata  
* Not interpreted or modified by AI (for now)

---

## **2.2 AI Quote**

### **Definition**

* Primary extracted content from the email

### **Role**

* Ground truth  
* Highest signal information

### **Rules**

* Derived from actual email content (plain or HTML)  
* Prefer structured, specific lines (times, locations, confirmations, amounts)  
* Must stand on its own

---

## **2.3 AI Summary**

### **Definition**

* One sentence interpretation

### **Role**

* Adds meaning or context  
* Helps user understand intent quickly

### **Rules**

* Must not repeat subject  
* Must not repeat quote  
* Must introduce new information (implication, guidance, or framing)  
* Always present (no conditional logic yet)

---

# **3\. Action Surface (Unified System)**

## **Core Idea**

One surface per card:

* CardButton (actionable)  
* CardLabel (informational)

---

## **3.1 CardButton**

### **Use when**

* A real, executable action exists

### **Rules**

* Only one primary button  
* Must map to a real action (link, deep link, etc.)  
* Label must reflect the action clearly

---

## **3.2 CardLabel**

### **Use when**

* No executable action exists  
* But interpretation is still useful

### **Rules**

* Represents understanding, not action  
* Short and clear  
* Replaces the need for a separate “status” system

---

## **3.3 Decision Rule**

* If executable action exists → CardButton  
* Else if meaningful interpretation exists → CardLabel  
* Else → no action surface

---

# **4\. Input Schema (AI Layer)**

type AIEmailInput \= {

  sender: {

    name: string;

    email: string;

    domain: string;

  };

  content: {

    subject: string;

    snippet: string;

    plainText?: string;

    htmlText?: string;

  };

  metadata: {

    hasPlain: boolean;

    hasHtml: boolean;

    timestamp: string;

  };

  signals: {

    links: string\[\];

    attachments: Array\<{ name?: string; mimeType?: string }\>;

    unsubscribePresent: boolean;

    senderDisplayMismatch: boolean;

  };

};

---

# **5\. Output Schema (Card Model)**

type EmailCard \= {

  header: {

    senderName: string;

    email: string;

    time: string;

    cardTag?: string;

  };

  content: {

    subject: string;

    quote: string;

    summary: string;

  };

  actionSurface:

    | { type: "button"; label: string; url: string }

    | { type: "label"; label: string }

    | { type: "none" };

};

---

# **6\. System Boundaries (Important)**

### **This spec defines:**

* Information hierarchy  
* Data roles  
* Decision logic  
* AI responsibilities

### **This spec does NOT define:**

* Typography  
* Visual weight  
* Spacing  
* Color  
* Layout styling

👉 Those belong to the design system, not the product logic.

---

This is cleaner now. You’ve separated:

* **What the system is doing (product logic)**  
* from  
* **How it looks (design system)**

That separation is exactly what’s going to let you scale this into a real system instead of a one-off UI.

# **Persona**

# **Angelica Vasquez**

## **North Star Persona — Communication Anxiety & Mental Freedom**

---

## **1\. Executive Summary**

Angelica represents a class of users for whom email is not a productivity problem, but an **emotional safety problem**.

She avoids her inbox not because she is busy or disorganized, but because:

Opening email exposes her to **unclear expectations, social pressure, and unpredictable effort**.

Her primary goal is not efficiency.

It is:

**To feel like nothing is hanging over her.**

If the product can make Angelica feel safe opening her inbox, it will work for nearly everyone else.

---

## **2\. Who She Is (Context That Shapes Behavior)**

Angelica is 40, married, and lives on the Upper West Side. Her husband is a product designer in big tech and often helps her navigate tasks, especially communication-heavy ones.

She spends most of her time caring for her father, who is in his 80s and dealing with serious health issues related to cancer. This creates a steady emotional backdrop. Her time is not structured by work, but her energy is not abundant.

She grew up in Inwood in a low-income household:

* Her mother did not speak English  
* Her older brother was involved in the streets  
* Her older sister was emotionally distant

In that environment, Angelica learned to:

* be careful  
* avoid mistakes  
* read people closely  
* not create additional problems

This became her default operating mode.

---

## **3\. Formative Experience: Photography**

Angelica once worked as a photographer and loved the craft itself.

But the job required:

* managing clients  
* directing people  
* communicating expectations  
* delivering work that would be judged

Over time, the emotional cost of these interactions outweighed the creative joy.

She stopped.

Not because she lacked skill, but because:

**Communication made the work feel unsustainable**

This experience shaped a lasting belief:

“Even things I’m good at can become overwhelming when they involve people.”

---

## **4\. Core Psychological Profile**

Angelica’s behavior is driven by a combination of well-understood patterns.

---

### **4.1 Intolerance of Uncertainty**

Unknowns feel like risk.

An unread email is not neutral. It is:

“Something I may not know how to handle yet”

---

### **4.2 Social Evaluation Sensitivity**

Every response is perceived as a performance.

She is not just answering:

* what to say  
* but how it will be interpreted

---

### **4.3 Avoidance Reinforcement Loop**

* Email creates anxiety  
* Avoiding reduces anxiety immediately  
* Brain learns: avoidance works  
* Next time, avoidance is more likely

---

### **4.4 Effort Inflation**

Before acting, she overestimates:

* how long something will take  
* how complex it will be  
* how draining it will feel

---

### **4.5 Open Loop Sensitivity**

Unresolved messages stay mentally active.

Even when she avoids email, she does not feel free.

---

## **5\. Current Behavioral Patterns**

These are the most important signals for product design.

---

### **5.1 Inbox Avoidance**

She frequently does not open her email app for long periods.

Opening the inbox feels like:

stepping into a space where multiple things will immediately demand something from her

---

### **5.2 Missing Important Emails**

As a result:

* she misses time-sensitive messages  
* responds late  
* occasionally drops threads

This reinforces:

“I’m probably already behind”

---

### **5.3 Over-Processing Responses**

When she does engage:

* she takes significantly longer than necessary  
* she hesitates before sending

---

### **5.4 Heavy Use of ChatGPT for Replies**

She often:

* pastes emails into ChatGPT  
* iterates on responses multiple times

A simple reply becomes a long session.

This is not about writing.

It is about:

**feeling confident she is not saying the wrong thing**

---

### **5.5 Energy-Based Engagement**

She only opens email when she feels:

* mentally ready  
* emotionally available

If she is tired or overwhelmed:

she avoids entirely

---

## **6\. Emotional Model of Email**

For Angelica, email is not information.

It is:

**A queue of potential obligations with unclear cost**

---

### **Before opening**

“I don’t know what’s in there, and I might not be ready for it”

---

### **While scanning**

“What does this want from me?”

---

### **When unclear**

“This is going to take effort I don’t understand yet”

---

### **When response is needed**

“I need to get this right”

---

### **After avoiding**

“I should’ve handled this already”

---

## **7\. The Core User Need**

Angelica is not trying to process email faster.

She is trying to reach a state:

**Nothing is mentally pulling on her**

---

### **What she wants:**

* to know what something means immediately  
* to know if she needs to act  
* to understand how much effort it will take  
* to feel safe not acting immediately  
* to trust she’s not missing something important

---

## **8\. Key Product Insight**

The primary problem is not volume.

It is:

**Ambiguity \+ perceived obligation \+ unclear effort**

---

## **9\. Design Implications**

If Angelica is the north star, the system must:

---

### **9.1 Reduce Uncertainty Before Exposure**

Before showing emails:

* set expectations  
* communicate overall state

Example:

* “Nothing urgent”  
* “1 thing may need your attention”

---

### **9.2 Externalize Meaning**

Every email must answer instantly:

* What is this?  
* What do they want?  
* Do I need to act?

---

### **9.3 Show Effort**

Not just intent.

But:

* “Takes 10 seconds”  
* “Quick reply”  
* “No action needed”

---

### **9.4 Replace Pressure with Guidance**

Avoid command language.

Use:

* “They’re asking for…”  
* “You can…”

---

### **9.5 Provide Response Scaffolding**

Help her know what to say.

Not by writing for her.

But by:

reducing ambiguity about what a good response looks like

---

### **9.6 Make Non-Action Explicit**

She must feel allowed to ignore.

Examples:

* “Optional”  
* “No action needed”  
* “You’re good here”

---

### **9.7 Reinforce Completion**

Completion must feel real.

Not:

* “Inbox zero”

But:

“Nothing is waiting on you”

---

## **10\. Anti-Patterns**

These will fail this persona.

---

### **❌ Pure efficiency systems**

Fast, but still feel like work

---

### **❌ Harsh or direct language**

“Action required” → triggers avoidance

---

### **❌ Ambiguous summaries**

If she has to think → failure

---

### **❌ Overly verbose AI**

More content \= more cognitive load

---

### **❌ Hidden prioritization**

She must trust what she sees immediately

---

## **11\. Decision Framework (For Teams)**

Use this to evaluate features:

---

1. Does this reduce uncertainty?  
2. Does this reduce perceived obligation?  
3. Does this make the next step obvious?  
4. Does this feel supportive, not demanding?  
5. Does this make it easier to open the app next time?

---

## **12\. Final Product Reframe**

This product is not:

**“A better email client”**

It is:

**A system that makes communication feel safe, bounded, and manageable**

---

## **Final Anchor**

Angelica is not avoiding email.

She is avoiding:

**unclear expectations she might not be able to handle correctly**

If the product removes that fear,

she will open it.

And if she opens it,

everything else becomes solvable.

