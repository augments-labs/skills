"""Outgoing email. In production send_email() calls the mail provider."""
OUTBOX = []


class SendError(Exception):
    pass


def send_email(to, subject, body):
    OUTBOX.append({"to": to, "subject": subject, "body": body})
