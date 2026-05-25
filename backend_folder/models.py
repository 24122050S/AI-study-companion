from pydantic import BaseModel

class ChatRequest(BaseModel):
    user_id: str
    notebook_id: str
    message: str

class ScoreRequest(BaseModel):
    user_id: str
    topic: str
    score: int
    total: int

class WeaknessRequest(BaseModel):
    user_id: str
    notebook_id: str
    wrong_questions: list

class AuthRequest(BaseModel):
    username: str
    password: str

class NoteRequest(BaseModel):
    user_id: str
    title: str
    content: str

class NotebookRequest(BaseModel):
    user_id: str
    title: str