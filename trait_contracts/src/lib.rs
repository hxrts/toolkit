//! Shared expansion logic for trait-surface proc macros.

#![forbid(unsafe_code)]

use proc_macro2::{Span, TokenStream};
use quote::quote;
use syn::{
    parse::{Parse, ParseStream},
    parse2, parse_quote, Error, Ident, ItemImpl, ItemTrait, Path, Receiver, TraitItem,
};

pub fn expand_purity(attr: TokenStream, item: TokenStream) -> TokenStream {
    let purity = match parse2::<PurityClass>(attr) {
        | Ok(purity) => purity,
        | Err(error) => return error.to_compile_error(),
    };
    let item_trait = match parse2::<ItemTrait>(item) {
        | Ok(item_trait) => item_trait,
        | Err(error) => return error.to_compile_error(),
    };

    if let Err(error) = validate_trait(&item_trait, purity) {
        return error.to_compile_error();
    }

    quote!(#item_trait)
}

pub fn expand_effect_trait(
    attr: TokenStream,
    item: TokenStream,
    support_path: Path,
    marker_name: Ident,
) -> TokenStream {
    if let Err(error) = reject_args("effect_trait", attr) {
        return error.to_compile_error();
    }

    let mut item_trait = match parse2::<ItemTrait>(item) {
        | Ok(item_trait) => item_trait,
        | Err(error) => return error.to_compile_error(),
    };
    let ident = item_trait.ident.clone();

    item_trait
        .supertraits
        .push(parse_quote!(::core::marker::Send));
    item_trait
        .supertraits
        .push(parse_quote!(::core::marker::Sync));
    item_trait.supertraits.push(parse_quote!('static));
    item_trait.items.push(parse_quote! {
        #[doc(hidden)]
        fn #marker_name(
            &self,
        ) -> #support_path::HandlerToken<Self, dyn #ident>
        where
            Self: Sized;
    });

    quote! {
        #item_trait

        impl #support_path::EffectDefinition for dyn #ident {}
    }
}

pub fn expand_effect_handler(
    attr: TokenStream,
    item: TokenStream,
    support_path: Path,
    marker_name: Ident,
) -> TokenStream {
    if let Err(error) = reject_args("effect_handler", attr) {
        return error.to_compile_error();
    }

    let item_impl = match parse2::<ItemImpl>(item) {
        | Ok(item_impl) => item_impl,
        | Err(error) => return error.to_compile_error(),
    };
    let trait_path = match &item_impl.trait_ {
        | Some((_, path, _)) => path.clone(),
        | None => {
            return Error::new_spanned(
                &item_impl.self_ty,
                "#[effect_handler] can only be applied to trait impls",
            )
            .to_compile_error();
        },
    };

    let mut item_impl = item_impl;
    let self_ty = item_impl.self_ty.clone();
    let generics = item_impl.generics.clone();
    let (impl_generics, _, where_clause) = generics.split_for_impl();

    item_impl.items.push(parse_quote! {
        fn #marker_name(
            &self,
        ) -> #support_path::HandlerToken<Self, dyn #trait_path>
        where
            Self: Sized,
        {
            #support_path::HandlerToken(::core::marker::PhantomData)
        }
    });

    quote! {
        #item_impl

        impl #impl_generics #support_path::HandlerDefinition<dyn #trait_path> for #self_ty #where_clause {}
    }
}

fn reject_args(name: &str, attr: TokenStream) -> syn::Result<()> {
    if attr.is_empty() {
        return Ok(());
    }

    Err(Error::new(
        Span::call_site(),
        format!("#[{name}] does not accept arguments"),
    ))
}

#[derive(Clone, Copy)]
enum PurityClass {
    Pure,
    ReadOnly,
    Effectful,
}

impl PurityClass {
    fn macro_form(self) -> &'static str {
        match self {
            | Self::Pure => "#[purity(pure)]",
            | Self::ReadOnly => "#[purity(read_only)]",
            | Self::Effectful => "#[purity(effectful)]",
        }
    }
}

impl Parse for PurityClass {
    fn parse(input: ParseStream<'_>) -> syn::Result<Self> {
        let ident = input.parse::<Ident>()?;
        match ident.to_string().as_str() {
            | "pure" => Ok(Self::Pure),
            | "read_only" => Ok(Self::ReadOnly),
            | "effectful" => Ok(Self::Effectful),
            | _ => Err(Error::new_spanned(
                ident,
                "expected one of: `pure`, `read_only`, `effectful`",
            )),
        }
    }
}

fn validate_trait(item_trait: &ItemTrait, purity: PurityClass) -> syn::Result<()> {
    let methods: Vec<_> = item_trait
        .items
        .iter()
        .filter_map(|item| match item {
            | TraitItem::Fn(method) => Some(method),
            | _ => None,
        })
        .collect();

    match purity {
        | PurityClass::Pure | PurityClass::ReadOnly => {
            for method in methods {
                reject_disallowed_receiver(method.sig.receiver(), purity)?;
            }
        },
        | PurityClass::Effectful => {
            if methods.is_empty() {
                return Ok(());
            }

            if !methods.iter().any(|method| {
                matches!(
                    method.sig.receiver(),
                    Some(Receiver { mutability: Some(_), .. })
                )
            }) {
                return Err(Error::new_spanned(
                    &item_trait.ident,
                    format!(
                        "{} requires at least one `&mut self` method",
                        purity.macro_form()
                    ),
                ));
            }
        },
    }

    Ok(())
}

fn reject_disallowed_receiver(
    receiver: Option<&Receiver>,
    purity: PurityClass,
) -> syn::Result<()> {
    if let Some(receiver) = receiver {
        if receiver.mutability.is_some() {
            return Err(Error::new_spanned(
                receiver,
                format!(
                    "{} does not allow `&mut self`; split mutable/runtime behavior into a separate trait",
                    purity.macro_form()
                ),
            ));
        }

        if receiver.reference.is_none() {
            return Err(Error::new_spanned(
                receiver,
                format!(
                    "{} does not allow by-value receivers; use `&self` or split the effectful method into a separate trait",
                    purity.macro_form()
                ),
            ));
        }
    }

    Ok(())
}
