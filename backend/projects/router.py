import uuid
import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import List, Optional

from db.models import Project, Scene
from auth.deps import get_current_user

log = logging.getLogger("loreweaver.projects")
router = APIRouter(prefix="/projects", tags=["projects"])


# ─── Schemas ──────────────────────────────────────────────────────────────────
class ProjectCreate(BaseModel):
    name: str
    description: Optional[str] = None

class ProjectOut(BaseModel):
    id: str
    name: str
    description: Optional[str]
    scene_count: int
    created_at: str

class SceneOut(BaseModel):
    id: str
    sequence_index: int
    prompt: str
    scene_text: str
    critic_report: Optional[dict]
    location: Optional[str]
    created_at: str


# ─── Dependency injected from main.py ─────────────────────────────────────────
def get_db():
    raise NotImplementedError("Override via app.dependency_overrides")


# ─── Routes ───────────────────────────────────────────────────────────────────
@router.post("", status_code=201, response_model=ProjectOut)
def create_project(
    body: ProjectCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    project = Project(
        id=str(uuid.uuid4()),
        name=body.name,
        description=body.description,
        user_id=current_user["user_id"],
    )
    db.add(project)
    db.commit()
    db.refresh(project)
    log.info(f"[create_project] {current_user['email']} created project '{body.name}'")
    return _project_out(project)


@router.get("", response_model=List[ProjectOut])
def list_projects(
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    projects = db.query(Project).filter_by(user_id=current_user["user_id"]).order_by(Project.created_at.desc()).all()
    return [_project_out(p) for p in projects]


@router.delete("/{project_id}", status_code=204)
def delete_project(
    project_id: str,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    project = db.query(Project).filter_by(id=project_id, user_id=current_user["user_id"]).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    db.delete(project)
    db.commit()
    log.info(f"[delete_project] Deleted project {project_id}")


@router.get("/{project_id}/scenes", response_model=List[SceneOut])
def list_scenes(
    project_id: str,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    # Verify ownership
    project = db.query(Project).filter_by(id=project_id, user_id=current_user["user_id"]).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    scenes = db.query(Scene).filter_by(project_id=project_id).order_by(Scene.sequence_index).all()
    return [_scene_out(s) for s in scenes]


@router.delete("/{project_id}/scenes/{scene_id}", status_code=204)
def delete_scene(
    project_id: str,
    scene_id: str,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    # Verify project ownership
    project = db.query(Project).filter_by(id=project_id, user_id=current_user["user_id"]).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    scene = db.query(Scene).filter_by(id=scene_id, project_id=project_id).first()
    if not scene:
        raise HTTPException(status_code=404, detail="Scene not found")

    db.delete(scene)
    db.commit()
    log.info(f"[delete_scene] Deleted scene {scene_id} from project {project_id}")


# ─── Helpers ──────────────────────────────────────────────────────────────────
def _project_out(p: Project) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "description": p.description,
        "scene_count": len(p.scenes),
        "created_at": p.created_at.isoformat() if p.created_at else "",
    }

def _scene_out(s: Scene) -> dict:
    return {
        "id": s.id,
        "sequence_index": s.sequence_index,
        "prompt": s.prompt,
        "scene_text": s.scene_text,
        "critic_report": s.critic_report,
        "location": s.location,
        "created_at": s.created_at.isoformat() if s.created_at else "",
    }
