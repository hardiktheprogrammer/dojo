use anyhow::Result;
use async_trait::async_trait;
use dojo_world::manifest::{Component, Manifest, System};
use starknet::core::types::FieldElement;

pub mod memory;
pub mod sql;

#[async_trait]
pub trait State {
    async fn load_from_manifest(&mut self, manifest: Manifest) -> Result<()>;
    async fn head(&self) -> Result<u64>;
    async fn set_head(&mut self, head: u64) -> Result<()>;
    async fn register_component(&mut self, component: Component) -> Result<()>;
    async fn register_system(&mut self, system: System) -> Result<()>;
    async fn set_entity(
        &mut self,
        component: FieldElement,
        partition: FieldElement,
        key: FieldElement,
        values: Vec<FieldElement>,
    ) -> Result<()>;
    async fn delete_entity(
        &mut self,
        component: FieldElement,
        partition: FieldElement,
        key: FieldElement,
    ) -> Result<()>;
    async fn entity(
        &self,
        component: FieldElement,
        partition: FieldElement,
        key: FieldElement,
    ) -> Result<Vec<FieldElement>>;
    async fn entities(
        &self,
        component: FieldElement,
        partition: FieldElement,
    ) -> Result<Vec<Vec<FieldElement>>>;
}